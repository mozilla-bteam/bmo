/** @jsx React.DOM */
var TodoTabs = (function() {
  var baseURL = "https://bugzilla.mozilla.org";
  var bugURL = baseURL + "/show_bug.cgi?id=";
  var attachURL = baseURL + "/attachment.cgi?id=";
  var reviewURL = baseURL + "/page.cgi?id=splinter.html&bug=" // +"&attachment=" + attachId;

  var TodoTabs = React.createClass({
    render: function() {
      return (
        <div id="todo-lists" className="tabs">
          <TabsNav tabs={this.props.tabs}
              selectedTab={this.props.selectedTab}
              data={this.props.data}
              onTabClick={this.handleTabClick}/>
          <TabsContent tabs={this.props.tabs}
              selectedTab={this.props.selectedTab}
              data={this.props.data}
              includeBlockedBugs={this.props.includeBlockedBugs}/>
        </div>
      );
    },
    handleTabClick: function(tabId) {
      this.props.onTabSelect(tabId);
    }
  });

  var TabsNav = React.createClass({
    render: function() {
      var selectedTab = this.props.selectedTab;

      var tabNodes = this.props.tabs.map(function(item, index) {
        var list = this.props.data[item.id];

        // display a count of the items and unseen items in this list
        var count = list.items ? list.items.length : "";
        var newCount = "";
        if (list.newCount) {
          newCount = (
            <span className="new-count">
              &nbsp;+{list.newCount}
            </span>
          );
        }

        var className = "tab" + (selectedTab == item.id ? " tab-selected" : "");

        return (
          <li>
            <a className={className} title={item.alt}
               onClick={this.onClick.bind(this, item.id)}>
              {item.name}
              <span className="count">
                {count}
              </span>
              {newCount}
            </a>
          </li>
        );
      }.bind(this));

      return (
        <nav className="tab-head">
          <ul>
            {tabNodes}
          </ul>
        </nav>
      );
    },
    onClick: function(index) {
      this.props.onTabClick(index);
    }
  });

  var TabsContent = React.createClass({
    render: function() {
      var panelNodes = this.props.tabs.map(function(tab, index) {
        var data = this.props.data[tab.id];

        var list;
        switch(tab.type) {
          case "patches":
            list = <PatchList data={data}/>;
            break;
          case "flags":
            list = <RespondList data={data}/>;
            break;
          case "flags+reviews":
            list = <NagList data={data}/>;
            break;
          case "bugs":
          default:
            list = <BugList data={data}
                      includeBlockedBugs={this.props.includeBlockedBugs}/>;
            break;
        }

        return (
          <div className={'tab-content ' + (this.props.selectedTab == tab.id ?
                          'tab-content-selected' : '')}>
            {list}
          </div>
        );
      }.bind(this));

      return (
        <div className="tab-body">
          {panelNodes}
        </div>
      );
    }
  });

  var BugList = React.createClass({
    render: function() {
      var items = this.props.data.items;
      if (items) {
        // filter out the blocked bugs, if pref is set
        if (!this.props.includeBlockedBugs) {
          items = items.filter(function(item) {
            return !item.bug.depends_on || !item.bug.depends_on.length;
          });
        }
        var listItems = items.map(function(item) {
          return (
            <ListItem isNew={item.new}>
              <BugItem bug={item.bug}/>
            </ListItem>
          );
        });
      }
      return (
        <List items={items}>
          {listItems}
        </List>
      );
    }
  });

  var NagList = React.createClass({
    render: function() {
      var items = this.props.data.items;
      if (items) {
        var listItems = items.map(function(item) {
          var flags = item.flags.map(function(flag) {
            return <FlagItem flag={flag}/>;
          });
          var patches = item.attachments.map(function(patch) {
            var patchFlags = patch.flags.map(function(flag) {
              return <FlagItem flag={flag}/>;
            });
            return (
              <div>
                <PatchItem patch={patch}/>
                {patchFlags}
              </div>
            );
          });
          var requests = patches.concat(flags);

          return (
            <ListItem isNew={item.new}>
              <BugItem bug={item.bug}/>
              <div>
                {requests}
              </div>
            </ListItem>
          );
        });
      }
      return (
        <List items={items}>
          {listItems}
        </List>
      );
    }
  });

  var RespondList = React.createClass({
    render: function() {
      var items = this.props.data.items;
      if (items) {
        var listItems = items.map(function(item) {
          var flags = item.bug.flags.map(function(flag) {
            return <FlagItem flag={flag}/>;
          });
          return (
            <ListItem isNew={item.new}>
              <BugItem bug={item.bug}/>
              <div>
                {flags}
              </div>
            </ListItem>
          );
        });
      }
      return (
        <List items={items}>
          {listItems}
        </List>
      );
    }
  });

  var PatchList = React.createClass({
    render: function() {
      var items = this.props.data.items;
      if (items) {
        var listItems = items.map(function(item) {
          var patches = item.attachments.map(function(patch) {
             return <PatchItem patch={patch}/>;
          });
          return (
            <ListItem isNew={item.new}>
              <BugItem bug={item.bug}/>
              <div>
                {patches}
              </div>
            </ListItem>
          );
        });
      }
      return (
        <List items={items}>
          {listItems}
        </List>
      );
    }
  });

  var List = React.createClass({
    render: function() {
      if (!this.props.items) {
        return <WaitingList/>;
      }
      if (this.props.items.length == 0) {
        return <EmptyList/>;
      }
      return (
        <div>
          {this.props.children}
        </div>
      );
    }
  })

  var WaitingList = React.createClass({
    render: function() {
      return (
        <div className="list-item">
          <img src='lib/indicator.gif' className='spinner'></img>
        </div>
      );
    }
  })

  var EmptyList = React.createClass({
    render: function() {
      return (
        <div className="list-item empty-message">
          No items to display
        </div>
      );
    }
  })

  var PatchItem = React.createClass({
    render: function() {
      var patch = this.props.patch;
      var size = Math.round(patch.size / 1000) + "KB";
      return (
        <div>
          <a className="att-link" href={attachURL + patch.id} target="_blank"
             title={patch.description + " - " + size}>
             patch by {patch.attacher.name}
          </a>
          <span className="att-suffix">
            <span className="att-date timeago" title={patch.last_change_time}>
              {patch.last_change_time}
            </span>
          </span>
        </div>
      );
    }
  });

  var FlagItem = React.createClass({
    render: function() {
      var flag = this.props.flag;
      return (
        <div className="flag">
          <span className="flag-name">
            {flag.name}
          </span>
          <span className="flag-status">
            {flag.status} &nbsp;
          </span>
          <span className="flag-requestee">
            {flag.requestee}
          </span>
        </div>
      );
    }
  });

  var BugItem = React.createClass({
    render: function() {
      var bug = this.props.bug;
      return (
        <div className="bug">
          <a className="bug-link" href={bugURL + bug.id}
             target="_blank" title={bug.status + " - " + bug.summary}>
            <span className="bug-id">
              {bug.id}
            </span>
            -&nbsp;
            <span className="full-bug bug-summary">
              {bug.summary}
            </span>
          </a>
          <span className="item-date timeago"
                title={bug.last_change_time}>
            {bug.last_change_time}
          </span>
        </div>
      );
    }
  });

  var ListItem = React.createClass({
    render: function() {
      return (
        <div className={"list-item " + (this.props.isNew ? "new-item" : "")}>
          {this.props.children}
        </div>
      );
    }
  });

  return TodoTabs;
})();
