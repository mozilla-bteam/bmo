# Configuration options for secbugstats tools
# This file needs to live next to all the other collection/processing scripts.
# There are also configuration settings in settings.cfg which I didn't combine
# here because Bash and Python read configs differently.

import urllib

# scripts location (where does this config file live?)
SCRIPTS_DIR = "/path/to/this/file"

# database settings
DB_HOST = ""
DB_USER = ""
DB_PASS = ""
DB_NAME = ""

# LDAP settings
LDAP_USER = "username@ldap.domain"
LDAP_PASS = "ldap_password"

# Email settings
# email address to send the report from
EMAIL_FROM = "secbugstats-noreply@mozilla.com"
# list of email addresses to send the report to
EMAIL_TO   = ["person1@example.com", "person2@example.com"]
SMTP_HOST = "smtp.example.org"
SMTP_PORT = 465 # change this if you don't want SSL

# Bugzilla account settings
BZ_USER = "username@bugzilla.account"
BZ_PASS = "bugzilla-password"
BZ_AUTH = urllib.urlencode({'username': BZ_USER,
                            'password': BZ_PASS})

# where to store the JSON files that curlbug.py downloads
JSONLOCATION = "/path/to/current/json"

# Selection criteria for various teams based on bug product and component.
# First item is team name, second is a SQL WHERE clause to identify bugs
# belonging to that team
TEAMS = [["Layout",
          "Details.product='Core' AND (Details.component LIKE 'layout%' OR Details.component LIKE 'printing%' OR Details.component IN ('Style System (CSS)','SVG','Video/Audio'))"],
         ["JavaScript",
          "Details.product='Core' AND (Details.component LIKE 'javascript%' OR Details.component IN ('Nanojit'))"],
         ["DOM",
          "Details.product='Core' AND (Details.component LIKE 'DOM%' OR Details.component LIKE 'xp toolkit%' OR Details.component IN ('Document Navigation','Editor','Embedding: Docshell','Event Handling','HTML: Form Submission','HTML: Parser','js-ctypes','RDF','Security','Security: CAPS','Selection','Serializers','Spelling checker','Web Services','XBL','XForms','XML','XPConnect','XSLT','XUL'))"],
         ["GFX",
          "Details.product='Core' AND (Details.component LIKE 'GFX%' OR Details.component LIKE 'canvas%' OR Details.component LIKE 'widget%' OR Details.component IN ('Graphics','Image: Painting','ImageLib','MathML'))"],
         ["Frontend",
          "Details.product='Firefox' OR Details.product='Toolkit' OR (Details.product='Core' AND (Details.component IN ('Form Manager','History: Global','Installer: XPInstall Engine','Security: UI')))"],
         ["Networking",
          "Details.product='Core' AND Details.component like 'Networking%'"],
         ["Mail",
          "Details.product='MailNews Core' OR Details.product='Thunderbird' OR (Details.product='Core' AND (Details.component like 'Mail%'))"],
         ["Architecture",
          "Details.product='Core' AND (Details.component IN ('File Handling','Geolocation','IPC','Java: OJI','jemalloc','Plug-ins','Preferences: Backend','String','XPCOM'))"],
         ["Crypto",
          "Details.product IN ('JSS','NSS','NSPR') OR (Details.product='Core' AND Details.component IN ('Security: PSM','Security: S/MIME'))"],
         ["Services",
          "Details.product='Mozilla Services'"],
         ["Mobile",
          "Details.product='Fennec'"]]
