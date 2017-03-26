# Configuration options for secbugstats tools
# This file needs to live next to all the other collection/processing scripts.
# There are also configuration settings in settings.cfg which I didn't combine
# here because Bash and Python read configs differently.

import urllib

# scripts location (where does this config file live?)
SCRIPTS_DIR = "/home/dveditz/secbugstats/scripts"

# database settings
DB_HOST = "localhost"
DB_USER = "secbug"
DB_PASS = ""
DB_NAME = "secbug"

# LDAP settings
LDAP_USER = ""
LDAP_PASS = ""

# Email settings
# email address to send the report from
EMAIL_FROM = "secbugstats-noreply@mozilla.com"
# list of email addresses to send the report to
EMAIL_TO   = ['security-group@mozilla.org']
SMTP_HOST = "smtp.mozilla.org"
SMTP_PORT = 25 # 465

# Bugzilla account settings
BZ_APIKEY = ""
BZ_AUTH = urllib.urlencode({'api_key': BZ_APIKEY, 'restriclogin': "true"})

# where to store the JSON files that curlbug.py downloads
JSONLOCATION = "/home/dveditz/bugdata/current"

# Selection criteria for various teams based on bug product and component
TEAMS = [["Layout",
          "Details.product='Core' AND (Details.component LIKE 'layout%' OR Details.component LIKE 'print%' OR Details.component LIKE 'widget%' OR Details.component IN ('CSS Parsing and Computation','Style System (CSS)','SVG','Internationalization','MathML'))"],
         ["Media",
         "Details.product='Core' AND (Details.component LIKE 'WebRTC%' OR Details.component LIKE 'Audio/Video%' OR Details.component='Web Audio')"],
         ["JavaScript",
          "Details.product='Core' AND (Details.component LIKE 'javascript%' OR Details.component IN ('Nanojit'))"],
         ["DOM",
          "Details.product='Core' AND (Details.component LIKE 'DOM%' OR Details.component LIKE 'xp toolkit%' OR Details.component IN ('Document Navigation','Drag and Drop','Editor','Event Handling','HTML: Form Submission','HTML: Parser','RDF','Security','Security: CAPS','Selection','Serializers','Spelling checker','Web Services','XBL','XForms','XML','XPConnect','XSLT','XUL'))"],
         ["GFX",
          "Details.product='Core' AND (Details.component LIKE 'GFX%' OR Details.component LIKE 'canvas%' OR Details.component LIKE 'Graphics%' OR Details.component IN ('Graphics','Image: Painting','ImageLib'))"],
         ["Frontend",
          "Details.product='Firefox' OR Details.product='Firefox for Metro' OR Details.product='Toolkit' OR (Details.product='Core' AND (Details.component IN ('Form Manager','History: Global','Identity','Installer: XPInstall Engine','Security: UI','Keyboard: Navigation')))"],
         ["Networking",
          "Details.product='Core' AND Details.component like 'Networking%'"],
         ["Mail",
          "Details.product='MailNews Core' OR Details.product='Thunderbird' OR (Details.product='Core' AND (Details.component like 'Mail%'))"],
         ["Other",
          "Details.product='Core' AND (Details.component IN ('DMD','File Handling','General','Geolocation','IPC','Java: OJI','jemalloc','js-ctypes','Memory Allocator','mfbt','mozglue','Permission Manager','Preferences: Backend','String','XPCOM','MFBT','Disability Access APIs','Rewriting and Analysis') OR Details.component LIKE 'Embedding%' OR Details.component LIKE '(HAL)')"],
         ["Crypto",
          "Details.product IN ('JSS','NSS','NSPR') OR (Details.product='Core' AND Details.component IN ('Security: PSM','Security: S/MIME'))"],
         ["Services",
          "Details.product IN ('Cloud Services','Mozilla Services')"],
         ["Plugins",
          "Details.product IN ('Plugins','External Software Affecting Firefox') OR (Details.product='Core' AND Details.component='Plug-ins')"],
         ["Boot2Gecko",
          "Details.product='Firefox OS' OR Details.product='Boot2Gecko'"],
         ["Mobile",
          "Details.product IN ('Fennec Graveyard','Firefox for Android','Android Background Services','Firefox for iOS','Focus')"]]
