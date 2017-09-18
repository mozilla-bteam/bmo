/**
 * For installing this app as an Open Web App, e.g. on FirefoxOS
 */
if (navigator.mozApps) {
  var checkIfInstalled = navigator.mozApps.getSelf();
  checkIfInstalled.onsuccess = function () {
    if (checkIfInstalled.result) {
      // Already installed
    } else {
      var install = document.querySelector("#install"),
      manifestURL = location.href.substring(0, location.href.lastIndexOf("/")) + "/manifest.webapp";
      install.className = "show-install";
      install.onclick = function () {
        var installApp = navigator.mozApps.install(manifestURL);
        installApp.onsuccess = function(data) {
          install.style.display = "none";
        };
        installApp.onerror = function() {
          alert("Install failed\n\n:" + installApp.error.name);
        };
      };
    }
  };
}


//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoidHJhbnNmb3JtZWQuanMiLCJzb3VyY2VzIjpbbnVsbF0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBOztHQUVHO0FBQ0gsSUFBSSxTQUFTLENBQUMsT0FBTyxFQUFFO0VBQ3JCLElBQUksZ0JBQWdCLEdBQUcsU0FBUyxDQUFDLE9BQU8sQ0FBQyxPQUFPLEVBQUUsQ0FBQztFQUNuRCxnQkFBZ0IsQ0FBQyxTQUFTLEdBQUcsWUFBWTtBQUMzQyxJQUFJLElBQUksZ0JBQWdCLENBQUMsTUFBTSxFQUFFOztLQUU1QixNQUFNO01BQ0wsSUFBSSxPQUFPLEdBQUcsUUFBUSxDQUFDLGFBQWEsQ0FBQyxVQUFVLENBQUM7TUFDaEQsV0FBVyxHQUFHLFFBQVEsQ0FBQyxJQUFJLENBQUMsU0FBUyxDQUFDLENBQUMsRUFBRSxRQUFRLENBQUMsSUFBSSxDQUFDLFdBQVcsQ0FBQyxHQUFHLENBQUMsQ0FBQyxHQUFHLGtCQUFrQixDQUFDO01BQzlGLE9BQU8sQ0FBQyxTQUFTLEdBQUcsY0FBYyxDQUFDO01BQ25DLE9BQU8sQ0FBQyxPQUFPLEdBQUcsWUFBWTtRQUM1QixJQUFJLFVBQVUsR0FBRyxTQUFTLENBQUMsT0FBTyxDQUFDLE9BQU8sQ0FBQyxXQUFXLENBQUMsQ0FBQztRQUN4RCxVQUFVLENBQUMsU0FBUyxHQUFHLFNBQVMsSUFBSSxFQUFFO1VBQ3BDLE9BQU8sQ0FBQyxLQUFLLENBQUMsT0FBTyxHQUFHLE1BQU0sQ0FBQztTQUNoQyxDQUFDO1FBQ0YsVUFBVSxDQUFDLE9BQU8sR0FBRyxXQUFXO1VBQzlCLEtBQUssQ0FBQyxxQkFBcUIsR0FBRyxVQUFVLENBQUMsS0FBSyxDQUFDLElBQUksQ0FBQyxDQUFDO1NBQ3RELENBQUM7T0FDSCxDQUFDO0tBQ0g7R0FDRixDQUFDO0FBQ0osQ0FBQyIsInNvdXJjZXNDb250ZW50IjpbIi8qKlxuICogRm9yIGluc3RhbGxpbmcgdGhpcyBhcHAgYXMgYW4gT3BlbiBXZWIgQXBwLCBlLmcuIG9uIEZpcmVmb3hPU1xuICovXG5pZiAobmF2aWdhdG9yLm1vekFwcHMpIHtcbiAgdmFyIGNoZWNrSWZJbnN0YWxsZWQgPSBuYXZpZ2F0b3IubW96QXBwcy5nZXRTZWxmKCk7XG4gIGNoZWNrSWZJbnN0YWxsZWQub25zdWNjZXNzID0gZnVuY3Rpb24gKCkge1xuICAgIGlmIChjaGVja0lmSW5zdGFsbGVkLnJlc3VsdCkge1xuICAgICAgLy8gQWxyZWFkeSBpbnN0YWxsZWRcbiAgICB9IGVsc2Uge1xuICAgICAgdmFyIGluc3RhbGwgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKFwiI2luc3RhbGxcIiksXG4gICAgICBtYW5pZmVzdFVSTCA9IGxvY2F0aW9uLmhyZWYuc3Vic3RyaW5nKDAsIGxvY2F0aW9uLmhyZWYubGFzdEluZGV4T2YoXCIvXCIpKSArIFwiL21hbmlmZXN0LndlYmFwcFwiO1xuICAgICAgaW5zdGFsbC5jbGFzc05hbWUgPSBcInNob3ctaW5zdGFsbFwiO1xuICAgICAgaW5zdGFsbC5vbmNsaWNrID0gZnVuY3Rpb24gKCkge1xuICAgICAgICB2YXIgaW5zdGFsbEFwcCA9IG5hdmlnYXRvci5tb3pBcHBzLmluc3RhbGwobWFuaWZlc3RVUkwpO1xuICAgICAgICBpbnN0YWxsQXBwLm9uc3VjY2VzcyA9IGZ1bmN0aW9uKGRhdGEpIHtcbiAgICAgICAgICBpbnN0YWxsLnN0eWxlLmRpc3BsYXkgPSBcIm5vbmVcIjtcbiAgICAgICAgfTtcbiAgICAgICAgaW5zdGFsbEFwcC5vbmVycm9yID0gZnVuY3Rpb24oKSB7XG4gICAgICAgICAgYWxlcnQoXCJJbnN0YWxsIGZhaWxlZFxcblxcbjpcIiArIGluc3RhbGxBcHAuZXJyb3IubmFtZSk7XG4gICAgICAgIH07XG4gICAgICB9O1xuICAgIH1cbiAgfTtcbn1cblxuIl19