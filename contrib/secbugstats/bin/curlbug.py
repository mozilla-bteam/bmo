#!/usr/bin/python
# Bugzilla API script that queries for the number of open bugs by category, e.g.
# Critical, High, Moderate, Low, as well as some additional tracking categories.
# Saves the JSON results on the filesystem for further processing

import httplib, urllib, urllib2, cookielib, string, time, re, sys, os, MySQLdb, \
    simplejson
from base64 import b64decode
from settings import *

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
c = db.cursor()

if "--debug" in sys.argv:
  # store the json files in /tmp and don't run SQL
  DEBUG = True
  JSONLOCATION = "/tmp"
else:
  DEBUG = False

opener = urllib2.build_opener(urllib2.HTTPCookieProcessor())

def fetchBugzillaPage(path):
    url = "https://api-dev.bugzilla.mozilla.org/latest/bug?%s&%s" % (path, BZ_AUTH)
    return opener.open(url).read()

# Queries to run:
# Keys are the category of bugs and values are the query params to send to the
# Bugzilla API.
tocheck = {"sg_critical" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Acritical&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Acritical",
           "sg_high" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Ahigh&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Ahigh",
           "sg_moderate" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Amoderate&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Amoderate",
           "sg_low" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Alow&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Alow",
           "sg_total" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Acritical%2C%20%5Bsg%3Ahigh%2C%20%5Bsg%3Amoderate%2C%20%5Bsg%3Alow&status_whiteboard_type=anywordssubstr&type-1-0-0=anyexact&type-1-1-0=anywordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Acritical%2C%20%5Bsg%3Ahigh%2C%20%5Bsg%3Amoderate%2C%20%5Bsg%3Alow",
           "sg_unconfirmed" : "bug_status=UNCONFIRMED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&field0-0-0=bug_group&field0-0-1=status_whiteboard&query_format=advanced&status_whiteboard=sg%3Aneedinfo&status_whiteboard_type=notregexp&type-1-0-0=anyexact&type-1-1-0=notregexp&type0-0-0=equals&type0-0-1=substring&value-1-0-0=UNCONFIRMED&value-1-1-0=sg%3Aneedinfo&value0-0-0=core-security&value0-0-1=%5Bsg%3A",
           "sg_needstriage" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&field0-0-0=bug_group&query_format=advanced&status_whiteboard=%5C%5Bsg%3A&status_whiteboard_type=notregexp&type-1-0-0=anyexact&type-1-1-0=notregexp&type0-0-0=equals&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5C%5Bsg%3A&value0-0-0=core-security",
           "sg_investigate" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Ainvestigat&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Ainvestigat",
           "sg_vector" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Avector&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Avector",
           "sg_needinfo" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&query_format=advanced&status_whiteboard=%5Bsg%3Aneed&status_whiteboard_type=allwordssubstr&type-1-0-0=anyexact&type-1-1-0=allwordssubstr&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Aneed",
           "sg_untouched" : "bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=bug_status&field-1-1-0=status_whiteboard&field0-0-0=days_elapsed&query_format=advanced&status_whiteboard=%5Bsg%3Acritical%2C%20%5Bsg%3Ahigh%2C%20%5Bsg%3Amoderate%2C%20%5Bsg%3Alow&status_whiteboard_type=anywordssubstr&type-1-0-0=anyexact&type-1-1-0=anywordssubstr&type0-0-0=greaterthan&value-1-0-0=UNCONFIRMED%2CNEW%2CASSIGNED%2CREOPENED&value-1-1-0=%5Bsg%3Acritical%2C%20%5Bsg%3Ahigh%2C%20%5Bsg%3Amoderate%2C%20%5Bsg%3Alow&value0-0-0=14",
           "sg_opened" : "chfield=%5BBug%20creation%5D&chfieldfrom=-1w&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field0-0-0=bug_group&field0-0-1=status_whiteboard&query_format=advanced&type0-0-0=equals&type0-0-1=substring&value0-0-0=core-security&value0-0-1=%5Bsg%3A",
            "sg_closed" : "chfield=resolution&chfieldfrom=-1w&chfieldto=Now&emailassigned_to1=1&emailassigned_to2=1&emailqa_contact2=1&emailreporter2=1&field-1-0-0=resolution&field0-0-0=bug_group&field0-0-1=status_whiteboard&query_format=advanced&resolution=FIXED&resolution=INVALID&resolution=WONTFIX&resolution=DUPLICATE&resolution=WORKSFORME&resolution=INCOMPLETE&resolution=EXPIRED&resolution=MOVED&type-1-0-0=anyexact&type0-0-0=equals&type0-0-1=substring&value-1-0-0=FIXED%2CINVALID%2CWONTFIX%2CDUPLICATE%2CWORKSFORME%2CINCOMPLETE%2CEXPIRED%2CMOVED&value0-0-0=core-security&value0-0-1=%5Bsg%3A",
           }

now = time.localtime()
timestamp_file = time.strftime('%Y%m%d%H%M', now)
timestamp_db = time.strftime('%Y-%m-%d %H:%M', now)

# Store the results for further processing (e.g. how many bugs per
# Product/Component?) but first save the number of results for the
# high-level stats.
for key, url in tocheck.items():
    print "Fetching", key
    # will retry Bugzilla queries if they fail
    attempt = 1
    count = None
    while count is None:
        if attempt > 1:
            print "Retrying %s - attempt %d" % (key, attempt)
        json = fetchBugzillaPage(url)
        # save a copy of the bugzilla query
        filename = timestamp_file+"_"+key+".json"
        fp = open(JSONLOCATION+"/"+filename, "w")
        fp.write(json)
        fp.close()
        # log the number of hits each query returned
        results = simplejson.loads(json)
        count = len(results["bugs"])
        attempt += 1
    sql = "INSERT INTO Stats(category, count, date) VALUES('%s', %s, '%s');" % \
          (key, count, timestamp_db)
    if DEBUG: print sql
    else: c.execute(sql)
