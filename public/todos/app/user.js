var BugzillaUser = (function() {
  function isPending(flag) {
    return flag.status == "?"
  }

  function isFlagMatchesUser(field, username) {
    var name = username.replace(/@.+/, "").toLowerCase();
    return function(flag) {
      return flag[field] &&
             flag[field].name &&
             flag[field].name.toLowerCase() == name
    }
  }

  function BugzillaUser(username, limit) {
    this.username = username;
    this.limit = limit;

    this.isSetter = isFlagMatchesUser("setter", username);
    this.isRequestee = isFlagMatchesUser("requestee", username);
    this.isAttacher = isFlagMatchesUser("attacher", username);

    this.client = bz.createClient({
      username: username
    });
  }

  BugzillaUser.prototype = {
    fields: 'id,summary,status,resolution,last_change_time'
  }

  BugzillaUser.prototype.component = function(product, component, callback) {
    this.client.searchBugs({
      product: product,
      component: component,
      include_fields: this.fields,
      limit: this.limit,
      order: "changeddate DESC",
    }, callback);
  }

  BugzillaUser.prototype.bugs = function(methods, callback) {
    var query = {
      email1: this.username,
      email1_type: "equals",
      order: "changeddate DESC",
      limit: this.limit,
      include_fields: this.fields
    };

    if (methods.indexOf('cced') >= 0) {
      query['email1_cc'] = 1;
    }
    if (methods.indexOf('assigned') >= 0) {
      query['email1_assigned_to'] = 1;
    }
    if (methods.indexOf('reporter') >= 0) {
      query['email1_reporter'] = 1;
    }
    this.client.searchBugs(query, callback);
  }

  BugzillaUser.prototype.fetchTodos = function(callback) {
    var total = 5;
    var count = 0; // lists fetched so far
    var data = {};

    this.toReview(function(err, requests) {
      if (err) throw err;
      data.review = {
        items: requests
      };
      if (++count == total) {
        callback(data);
      }
    });
    this.toCheckin(function(err, requests) {
      if (err) throw err;
      data.checkin = {
        items: requests
      };
      if (++count == total) {
        callback(data);
      }
    });
    this.toNag(function(err, requests) {
      if (err) throw err;
      data.nag = {
        items: requests
      };
      if (++count == total) {
        callback(data);
      }
    });
    this.toRespond(function(err, requests) {
      if (err) throw err;
      data.respond = {
        items: requests
      };
      if (++count == total) {
        callback(data);
      }
    });
    this.toFix(function(err, requests) {
      if (err) throw err;
      data.fix = {
        items: requests
      };
      if (++count == total) {
        callback(data);
      }
    });
  }

  BugzillaUser.prototype.toReview = function(callback) {
    var isRequestee = this.isRequestee;

    this.client.searchBugs({
        'field0-0-0': 'flag.requestee',
        'type0-0-0': 'contains',
        'value0-0-0': this.username,
        status: ['NEW', 'UNCONFIRMED', 'REOPENED', 'ASSIGNED'],
        include_fields: 'id,summary,status,resolution,last_change_time,attachments'
      },
      function(err, bugs) {
        if (err) {
          return callback(err);
        }

        var requests = [];

        bugs.forEach(function(bug) {
          // only add attachments with this user as requestee
          if (!bug.attachments) {
            return;
          }
          /* group attachments together for this bug */
          var atts = [];
          bug.attachments.forEach(function(att) {
            if (att.is_obsolete || !att.flags) {
              return;
            }
            att.flags.some(function(flag) {
              if (isPending(flag) && isRequestee(flag)) {
                att.bug = bug;
                att.type = flag.name;
                att.time = att.last_change_time;
                atts.push(att);
                return true;
              }
              return false;
            });
          });

          if (atts.length) {
            requests.push({
              bug: bug,
              attachments: atts,
              time: atts[0].last_change_time
            })
          }
        });
        requests.sort(compareByTime);

        callback(null, requests);
      });
  }

  BugzillaUser.prototype.toCheckin = function(callback) {
    var isAttacher = this.isAttacher;

    this.client.searchBugs({
        'field0-0-0': 'attachment.attacher',
        'type0-0-0': 'equals',
        'value0-0-0': this.username,
        'field0-1-0': 'whiteboard',
        'type0-1-0': 'not_contains',
        'value0-1-0': 'fixed',
        'field0-2-0': 'flagtypes.name',
        'type0-2-0': 'substring',
        'value0-2-0': 'review+',
        status: ['NEW', 'UNCONFIRMED', 'REOPENED', 'ASSIGNED'],
        include_fields: 'id,summary,status,resolution,last_change_time,attachments'
      },
      function(err, bugs) {
        if (err) {
          return callback(err);
        }

        var requests = [];

        function readyToLand(att) {
          if (att.is_obsolete || !isCodeAttachment(att) || !att.flags || !isAttacher(att)) {
            return false;
          }

          // Do we have at least one review+?
          var ready = att.flags.filter(function(flag) {
            return flag.name == "review" && flag.status == "+";
          }).length > 0;

          if (!ready)
            return false;

          // Don't add patches that have pending requests, have review-, or have
          // checkin+.
          for (var i = 0; i < att.flags.length; ++i) {
            var flag = att.flags[i];
            if (flag.status == "?" && flag.name != "checkin" || flag.name == "review" && flag.status == "-" || flag.name == "checkin" && flag.status == "+") {
              return false;
            }
          }

          return ready;
        }

        bugs.forEach(function(bug) {
          var atts = [];
          bug.attachments.forEach(function(att) {
            if (!readyToLand(att)) {
              return;
            }
            att.bug = bug;
            atts.push(att);
          });

          if (atts.length) {
            requests.push({
              bug: bug,
              attachments: atts,
              time: atts[0].last_change_time
            })
          }
        });
        requests.sort(compareByTime);

        callback(null, requests);
      });
  }

  /**
   * All the patches and bugs the user is awaiting action on
   * (aka they have a outstanding flag request)
   */
  BugzillaUser.prototype.toNag = function(callback) {
    var isSetter = this.isSetter;
    var isRequestee = this.isRequestee;


    this.client.searchBugs({
      'field0-0-0': 'flag.setter',
      'type0-0-0': 'equals',
      'value0-0-0': this.username,
      'field0-0-1': 'attachment.attacher',
      'type0-0-1': 'equals',
      'value0-0-1': this.username,
      'field0-1-0': 'flagtypes.name',
      'type0-1-0': 'contains',
      'value0-1-0': '?',
      status: ['NEW', 'UNCONFIRMED', 'REOPENED', 'ASSIGNED'],
      include_fields: 'id,summary,status,resolution,last_change_time,flags,attachments'
    }, function(err, bugs) {
      var requests = [];

      bugs.forEach(function(bug) {
        var atts = [];
        var flags = [];

        if (bug.flags) {
          bug.flags.forEach(function(flag) {
            if (isPending(flag) && isSetter(flag) && !isRequestee(flag) && flag.name != "in-testsuite") {
              flags.push(flag);
            }
          });
        }
        if (bug.attachments) {
          bug.attachments.forEach(function(att) {
            if (att.is_obsolete || !att.flags) {
              return;
            }

            att.flags.some(function(flag) {
              if (isPending(flag) && isSetter(flag)) {
                att.bug = bug;
                atts.push(att);
                return true;
              }
              return false;
            })
          });
        }

        if (atts.length || flags.length) {
          requests.push({
            bug: bug,
            attachments: atts,
            flags: flags,
            time: bug.last_change_time
          });
        }
      })
      requests.sort(compareByTime);

      callback(null, requests);
    })
  }

  BugzillaUser.prototype.toFix = function(callback) {
    var query = {
      email1: this.username,
      email1_type: "equals",
      email1_assigned_to: 1,
      'field0-1-0': 'whiteboard',
      'type0-1-0': 'not_contains',
      'value0-1-0': 'fixed',
      order: "changeddate DESC",
      status: ['NEW', 'UNCONFIRMED', 'REOPENED', 'ASSIGNED'],
      include_fields: 'id,summary,status,resolution,last_change_time,attachments,depends_on'
    };
    var self = this;
    this.client.searchBugs(query, function(err, bugs) {
      if (err) {
        return callback(err);
      }

      var bugsToFix = bugs.filter(function(bug) {
        if (!bug.attachments) {
          return true;
        }

        var patchForReview = bug.attachments.some(function(att) {
          if (att.is_obsolete || !isCodeAttachment(att) || !att.flags) {
            return false;
          }
          var reviewFlag = att.flags.some(function(flag) {
            return flag.name == "review" && (flag.status == "?" ||
              flag.status == "+");
          });
          var checkedIn = att.flags.some(function(flag) {
            return flag.name == "checkin" && flag.status == "+";
          });
          return reviewFlag && !checkedIn;
        });
        return !patchForReview;
      });

      self.fetchDeps(bugsToFix, function() {
        bugsToFix.sort(function(b1, b2) {
          return new Date(b2.last_change_time) - new Date(b1.last_change_time);
        });

        bugsToFix = bugsToFix.map(function(bug) {
          return {
            bug: bug
          };
        })
        callback(null, bugsToFix);
      });
    });
  }

  // Fetch all of each bugs dependencies and modify in place each bug's depends_on
  // array so that it only contains OPEN bugs that it depends on.
  BugzillaUser.prototype.fetchDeps = function(bugs, callback) {
    // The number of bug requests we are waiting on.
    var waiting = 0;

    // Helper function to call the callback when we are no longer waiting for
    // any more bug requests.
    function maybeFinish() {
      if (waiting) return;
      callback();
    }

    var self = this;
    bugs.forEach(function(bug) {
      if (!bug.depends_on) {
        return;
      }

      var oldDeps = bug.depends_on;
      bug.depends_on = [];
      oldDeps.forEach(function(dep) {
        waiting++;
        self.client.getBug(dep, function(err, depBug) {
          try {
            if (err) {
              // Private bugs have an err of "HTTP status 400", so ignore such cases.
              // Upstream https://github.com/harthur/bz.js/issues/17 filed for making
              // the bz.js response more clear for these.
              if (err === "HTTP status 400") {
                return;
              }
              throw err;
            }
            if (depBug.status === "RESOLVED") {
              return;
            }
            bug.depends_on.push(depBug);
          } finally {
            // Make sure we check for completion even in the case of errors & resolved bugs.
            waiting--;
            maybeFinish();
          }
        });
      });
    });

    // Check if we're all done, in case there were no dependant bugs.
    // Failing that we'll check again via the dependant bugs' getBug() callback.
    maybeFinish();
  };

  BugzillaUser.prototype.toRespond = function(callback) {
    var isRequestee = this.isRequestee;

    this.client.searchBugs({
        'field0-0-0': 'flag.requestee',
        'type0-0-0': 'equals',
        'value0-0-0': this.username,
        include_fields: 'id,summary,status,resolution,last_change_time,flags'
      },
      function(err, bugs) {
        if (err) {
          return callback(err);
        }
        var flags = [];
        bugs.forEach(function(bug) {
          if (!bug.flags) {
            return;
          }
          bug.flags.forEach(function(flag) {
            if (isRequestee(flag)) {
              flags.push({
                name: flag.name,
                flag: flag,
                bug: bug,
                time: bug.last_change_time
              })
            }
          });
        });
        flags.sort(function(f1, f2) {
          return new Date(f2.time) - new Date(f1.time);
        });

        callback(null, flags);
      });
  }

  function isCodeAttachment(att) {
    return att.is_patch || att.content_type == "text/x-github-pull-request" || att.content_type == "text/x-review-board-request";
  }

  function compareByTime(event1, event2) {
    return new Date(event2.time) - new Date(event1.time);
  }

  return BugzillaUser;
})();
