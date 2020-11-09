Bugzilla Information
====================

These methods are used to get general configuration information about this
Bugzilla instance.

Version
-------

Returns the current version of Bugzilla. Normally in the format of ``X.X`` or
``X.X.X``. For example, ``4.4`` for the initial release of a new branch. Or
``4.4.6`` for a minor release on the same branch.

**Request**

.. code-block:: text

   GET /rest/version

**Response**

.. code-block:: js

   {
     "version": "4.5.5+"
   }

=======  ======  =========================================
name     type    description
=======  ======  =========================================
version  string  The current version of this Bugzilla
=======  ======  =========================================

Extensions
----------

Gets information about the extensions that are currently installed and enabled
in this Bugzilla.

**Request**

.. code-block:: text

   GET /rest/extensions

**Response**

.. code-block:: js

   {
     "extensions": {
       "Voting": {
         "version": "4.5.5+"
       },
       "BmpConvert": {
         "version": "1.0"
       }
     }
   }

==========  ======  ====================================================
name        type    description
==========  ======  ====================================================
extensions  object  An object containing the extensions enabled as keys.
                    Each extension object contains the following keys:

                    * ``version`` (string) The version of the extension.
==========  ======  ====================================================

Timezone
--------

Returns the timezone in which Bugzilla expects to receive dates and times on the API.
Currently hard-coded to UTC ("+0000"). This is unlikely to change.

**Request**

.. code-block:: text

   GET /rest/timezone

.. code-block:: js

   {
     "timezone": "+0000"
   }

**Response**

========  ======  ===============================================================
name      type    description
========  ======  ===============================================================
timezone  string  The timezone offset as a string in (+/-)XXXX (RFC 2822) format.
========  ======  ===============================================================

Time
----

Gets information about what time the Bugzilla server thinks it is, and
what timezone it's running in.

**Request**

.. code-block:: text

   GET /rest/time

**Response**

.. code-block:: js

   {
     "web_time_utc": "2014-09-26T18:01:30Z",
     "db_time": "2014-09-26T18:01:30Z",
     "web_time": "2014-09-26T18:01:30Z",
     "tz_offset": "+0000",
     "tz_short_name": "UTC",
     "tz_name": "UTC"
   }

=============  ======  ==========================================================
name           type    description
=============  ======  ==========================================================
db_time        string  The current time in UTC, according to the Bugzilla
                       database server.

                       Note that Bugzilla assumes that the database and the
                       webserver are running in the same time zone. However,
                       if the web server and the database server aren't
                       synchronized or some reason, *this* is the time that
                       you should rely on or doing searches and other input
                       to the WebService.
web_time       string  This is the current time in UTC, according to
                       Bugzilla's web server.

                       This might be different by a second from ``db_time``
                       since this comes from a different source. If it's any
                       more different than a second, then there is likely
                       some problem with this Bugzilla instance. In this
                       case you should rely  on the ``db_time``, not the
                       ``web_time``.
web_time_utc   string  Identical to ``web_time``. (Exists only for
                       backwards-compatibility with versions of Bugzilla
                       before 3.6.)
tz_name        string  The literal string ``UTC``. (Exists only for
                       backwards-compatibility with versions of Bugzilla
                       before 3.6.)
tz_short_name  string  The literal string ``UTC``. (Exists only for
                       backwards-compatibility with versions of Bugzilla
                       before 3.6.)
tz_offset      string  The literal string ``+0000``. (Exists only for
                       backwards-compatibility with versions of Bugzilla
                       before 3.6.)
=============  ======  ==========================================================

Job Queue Status
----------------

Reports the status of the job queue.

**Request**

.. code-block:: text

   GET /rest/jobqueue_status

This method requires an authenticated user.

**Response**

.. code-block:: js

   {
     "total": 12,
     "errors": 0
   }

===============  =======  ====================================================
name             type     description
===============  =======  ====================================================
total            integer  The total number of jobs in the job queue.
errors           integer  The number of errors produced by jobs in the queue.
===============  =======  ====================================================
