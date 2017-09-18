/** @jsx React.DOM */
var TodosApp = (function() {
  var tabs = [
    { id: "review",
      name: "To Review",
      alt: "Patches you have to review (key: r)",
      type: "patches"
    },
    { id: "checkin",
      name: "To Check In",
      alt: "Patches by you, ready to check in (key: c)",
      type: "patches"
    },
    { id: "nag",
      name: "To Nag",
      alt: "Patches by you, awaiting review (key: n)",
      type: "flags+reviews"
    },
    { id: "respond",
      name: "To Respond",
      alt: "Bugs where you're a flag requestee (key: p)",
      type: "flags"
    },
    { id: "fix",
      name: "To Fix",
      alt: "Bugs assigned to you (key: f)",
      type: "bugs"
    }
  ];

  var TodosStorage = {
    get email() {
      return localStorage['bztodos-email'];
    },

    set email(address) {
      localStorage["bztodos-email"] = address;
    },

    get selectedTab() {
      return localStorage['bztodos-selected-tab'];
    },

    set selectedTab(id) {
      localStorage['bztodos-selected-tab'] = id;
    },

    get includeBlockedBugs() {
      // default is true
      return !(localStorage['bztodos-include-blocked-bugs'] === "false");
    },

    set includeBlockedBugs(shouldInclude) {
      localStorage['bztodos-include-blocked-bugs'] = JSON.stringify(shouldInclude);
    },

    get notifications() {
      // default is false
      var result = (localStorage['bztodos-notifications'] === 'true');
      if (result) {
        maybeAskNotifcationPermission();
      }
      return result;
    },

    set notifications(shouldNotify) {
      if (shouldNotify) {
        maybeAskNotifcationPermission();
      }
      localStorage['bztodos-notifications'] = JSON.stringify(!!shouldNotify);
    }
  }

  var TodosApp = React.createClass({
    handleLoginSubmit: function(email) {
      if (!email || email == TodosStorage.email) {
        return;
      }
      this.setState(this.getInitialState());
      this.setUser(email);
    },

    handleTabSelect: function(listId) {
      if (listId == TodosStorage.selectedTab) {
        return;
      }
      TodosStorage.selectedTab = listId;
      this.setState({selectedTab: listId});
    },

    getInitialState: function() {
      return {
        data: {review: {}, checkin: {}, nag: {}, respond: {}, fix: {}},
        selectedTab: TodosStorage.selectedTab || "review",
        includeBlockedBugs: TodosStorage.includeBlockedBugs,
        notifications: TodosStorage.notifications
      };
    },

    componentDidMount: function() {
      var email = this.loadUser();
      if (!email) {
        $("#login-container").addClass("logged-out");
        $("#todo-lists").hide();
        $("footer").hide();
      }
      else {
        this.setUser(email);
      }

      // When they switch to another browser tab, mark all items as "seen"
      $(window).blur(function() {
        this.markAsSeen();
        this.updateTitle(0);
      }.bind(this));

      this.addKeyBindings();
      this.setupPreferences();

      // Update the todo lists every so often
      setInterval(this.update, this.props.pollInterval);
    },

    componentDidUpdate: function() {
      // turn timestamps into human times
      $(".timeago").timeago();
    },

    render: function() {
      return (
        <div>
          <TodosLogin onLoginSubmit={this.handleLoginSubmit}/>
          <TodoTabs tabs={tabs} data={this.state.data}
                    selectedTab={this.state.selectedTab}
                    includeBlockedBugs={this.state.includeBlockedBugs}
                    notifications={this.state.notifications}
                    onTabSelect={this.handleTabSelect}/>
        </div>
      );
    },

    /**
     * Get the user's email from the current url or storage.
     */
    loadUser: function() {
      // first see if the user is specified in the url
      var query = queryFromUrl();
      var email = query['email'];
      if (!email) {
        email = query['user'];
      }
      // if not, fetch the last user from storage
      if (!email) {
        email = TodosStorage.email;
        if (!email) {
          return null;
        }
      }
      return email;
    },

    /**
     * Reset the user by email, fetching new data and updating the lists.
     */
    setUser: function(email) {
      this.user = new BugzillaUser(email);

      TodosStorage.email = email;

      $("#login-container").removeClass("logged-out");
      $("#login-container").addClass("logged-in");
      $("#login-name").val(email);

      $("#welcome-message").hide();
      $("#todo-lists").show();
      $("footer").show();

      this.update();
    },

    /**
     * Fetch new data from Bugzilla and update the todo lists.
     */
    update: function() {
      this.user.fetchTodos(function(data) {
        var count = this.markNew(data);
        this.updateTitle(count);

        this.setState({data: data});
      }.bind(this));
    },

    /**
     * Mark which items in the fetched data are new since last time.
     * We need this to display the count of new items in the tab title
     * and favicon, and to visually highlight the new items in the list.
     */
    markNew: function(newData) {
      var oldData = this.state.data;
      var totalNew = 0; // number of new non-seen items

      for (var id in newData) {
        var newList = newData[id].items;
        var oldList = oldData[id].items;
        var newCount = 0;

        if (!newList || !oldList) {
          continue;
        }
        for (var i in newList) {
          // try to find this item in the old list
          var newItem = newList[i];
          var oldItem = null;
          for (var j in oldList) {
            if (newItem.bug.id == oldList[j].bug.id) {
              oldItem = oldList[j];
              break;
            }
          }
          // mark as new if there was no match in the old list, or
          // there is, but that item hasn't been seen yet by the user.
          var isNew = !oldItem || oldItem.new;
          if (isNew) {
            newCount++;
            totalNew++;
          }
          newItem.new = isNew;
        }
        // cache the count of new items for easy fetching
        newData[id].newCount = newCount;
      }

      if (totalNew > 0 && this.state.notifications && window.Notification && window.Notification.permission === 'granted') {
        new Notification('+' + totalNew + ' bugs in ' + document.title);
      }

      return totalNew;
    },

    /**
     * Mark every item as "seen", thus clearing favicon and title counts
     * and removing the highlights from new items.
     */
    markAsSeen: function() {
      // mutate old state briefly
      var data = this.state.data;
      for (var id in data) {
        var list = data[id].items;
        if (!list) {
          continue;
        }

        for (var i in list) {
          list[i].new = false;
        }
      }
      // then reset state to old state but without markers
      this.setState(data);
    },

    /**
     * Update the page title to reflect the number of updates.
     */
    updateTitle: function(updateCount) {
      var title = document.title;
      title = title.replace(/\(\w+\) /, "");

      // update title with the number of new requests
      if (updateCount) {
        title = "(" + updateCount + ") " + title;
      }
      document.title = title;

      // update favicon too
      Tinycon.setBubble(updateCount);
    },

    /**
     * Start listening for key events for changing tabs.
     */
    addKeyBindings: function() {
      var keys = {
        'r': 'review',
        'c': 'checkin',
        'n': 'nag',
        'p': 'respond',
        'f': 'fix',
        'h': 'selectPreviousTab',
        'l': 'selectNextTab',
      };

      $(document).keypress(function(e) {
        if (e.ctrlKey || e.altKey || e.shiftKey || e.metaKey
           || e.target.nodeName.toLowerCase() == "input") {
          return;
        }
        var action = keys[String.fromCharCode(e.charCode)];
        if (!action) {
          return;
        }
        if (this.indexForTab(action) >= 0) {
          return void this.handleTabSelect(action);
        }
        if (typeof this[action] == "function") {
          return void this[action]();
        }
      }.bind(this));

      // Tell the user what keybindings exist.
      var keyInfo = $("#key-info");
      var firstIteration = true;
      for (var key in keys) {
        if (firstIteration) {
          firstIteration = false;
        } else {
          keyInfo.append(", ");
        }
        keyInfo.append($("<code>").append(key));
      }
    },

    selectNextTab: function() {
      this.selectTabRelative(1);
    },

    selectPreviousTab: function() {
      this.selectTabRelative(-1);
    },

    selectTabRelative: function (offset) {
      var N = tabs.length;
      var index = this.indexForTab(this.state.selectedTab);
      var tab = tabs[(index + offset + N) % N];

      this.handleTabSelect(tab.id);
    },

    indexForTab: function(listId) {
      for (var i = 0; i < tabs.length; i++) {
        if (tabs[i].id == listId) {
          return i;
        }
      }
      return -1;
    },

    setupPreferences: function () {
      var checkbox = $("#include-blocked-bugs");
      checkbox.attr("checked", TodosStorage.includeBlockedBugs);
      checkbox.change(this.setIncludeBlockedBugs);

      if (window.Notification) {
        var notifications = $("#notifications");
        notifications.attr("checked", TodosStorage.notifications);
        notifications.change(this.setNotifications);
      } else {
        // No notifications available.
        $("#notifications-container").css({display: "none"});
      }
    },

    setIncludeBlockedBugs: function(event) {
      var shouldInclude = event.target.checked;
      TodosStorage.includeBlockedBugs = shouldInclude;

      this.setState({includeBlockedBugs: shouldInclude});
    },

    setNotifications: function(event) {
      var shouldNotify = event.target.checked;
      TodosStorage.notifications = shouldNotify;

      this.setState({notifications: shouldNotify});
    }
  });

  var TodosLogin = React.createClass({
    /**
     * Handle login form submission. We're using a form here so we can take
     * advantage of the browser's native autocomplete for remembering emails.
     */
    handleSubmit: function(e) {
      e.preventDefault();

      var email = this.refs.email.getDOMNode().value.trim();
      this.props.onLoginSubmit(email);

      // We do all this so we get the native autocomplete for the email address
      // http://stackoverflow.com/questions/8400269/browser-native-autocomplete-for-ajaxed-forms
      var iFrameWindow = document.getElementById("submit-iframe").contentWindow;
      var cloned = document.getElementById("login-form").cloneNode(true);
      iFrameWindow.document.body.appendChild(cloned);
      var frameForm = iFrameWindow.document.getElementById("login-form");
      frameForm.onsubmit = null;
      frameForm.submit();
      return false;
    },

    componentDidMount: function() {
      var input = $(this.refs.email.getDOMNode());
      input.val(TodosStorage.email);

      input.click(function(){
        this.select();
      });
      // clicking outside of the login should change the user
      input.blur(function() {
        $("#login-form").submit();
      });
      // React won't catch the submission fired from the blur handler
      $("#login-form").submit(this.handleSubmit);
    },

    render: function() {
      return (
        <div id="login-container">
          <span id="title">
            <img id="bug-icon" src="lib/bugzilla.png" alt="Bugzilla"></img>
             Todos
          </span>
          <span id="login"> for
            <form id="login-form" onSubmit={this.handleSubmit}>
              <input id="login-name"
                     name="email" placeholder="Enter Bugzilla user..."
                     ref="email"/>
            </form>
          </span>
        </div>
      );
    }
  })

  /**
   * Get an object with the query paramaters and values for the current page.
   */
  function queryFromUrl(url) {
    var vars = (url || document.URL).replace(/.+\?/, "").split("&"),
        query = {};
    for (var i = 0; i < vars.length; i++) {
      var pair = vars[i].split("=");
      query[pair[0]] = decodeURIComponent(pair[1]);
    }
    return query;
  }

  function maybeAskNotifcationPermission() {
    if (window.Notification && Notification.permission !== 'granted') {
      Notification.requestPermission(function (status) {
        if (Notification.permission !== status) {
          Notification.permission = status;
        }
      });
    }
  }

  return TodosApp;
})();

$(document).ready(function() {
  var interval = 1000 * 60 * 5; // 5 minutes

  React.render(<TodosApp pollInterval={interval}/>,
               document.getElementById("content"))
});
