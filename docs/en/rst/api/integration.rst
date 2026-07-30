.. _integration-best-practices:

Integration Best Practices
==========================

Use supported interfaces
------------------------

Use the :doc:`documented native REST API <core/v1/index>` for new integrations.
BzAPI remains available as a compatibility layer, but it is deprecated.
Existing BzAPI integrations should migrate to the native REST API. If immediate
migration is not possible, use BMO's built-in ``/bzapi/`` compatibility
endpoint prefix instead of the retired standalone BzAPI service. The
compatibility layer performs additional request and response translation.

Do not rely on scraped HTML, bug lists exported as CSV or XML, or undocumented
endpoints when your integration requires a stable interface. Use documented
REST API methods that are not marked experimental. See the :ref:`API overview
<api-list>` for the other interfaces that Bugzilla provides.

Use a dedicated bot account
---------------------------

Do not reuse a person's account for automation. Human accounts may acquire
privileges that the integration does not need. Request a dedicated bot account
by `filing an Administration bug
<https://bugzilla.mozilla.org/enter_bug.cgi?product=bugzilla.mozilla.org&component=Administration>`_.
Grant the account only the privileges required by the integration.

Authenticate with an API key in the ``X-BUGZILLA-API-KEY`` request header.
Do not put API keys in URLs, where they can be captured in logs and browser
history. See :ref:`REST API authentication <rest-authentication>` for details.

Poll responsibly
-----------------

Do not poll BMO more frequently than once every five minutes. If an integration
needs lower-latency updates, use the :doc:`Webhooks API
<../extensions/Webhooks/api/v1/index>`. Contact the BMO team in the
`BMO Matrix channel <https://chat.mozilla.org/#/room/#bmo:mozilla.org>`_ to
discuss requirements that the documented webhooks do not meet.

Poll incrementally instead of repeating a full search. The
``last_change_time`` parameter to :ref:`rest_search_bugs` returns bugs modified
at or after the supplied timestamp. Bug searches may use a read replica, while
``GET /rest/time`` reads the primary database. Because BMO does not guarantee a
maximum replication lag, an integration that requires a guaranteed polling
window should confirm the current operational guidance with the BMO team.
A polling cycle should:

* obtain BMO's current ``db_time`` from :ref:`GET /rest/time <rest-time>`
  before searching;
* search from at least five minutes before the previous successful cycle's
  recorded time, unless the BMO team has confirmed a different overlap;
* pass ``order=bug_id``, choose a ``limit`` of 10,000 or less, and
  page with ``limit`` and ``offset`` until a page contains fewer than ``limit``
  bugs. The response does not indicate when more results are available;
* collect the bug IDs from every page, then fetch and process every unique bug
  before saving the new ``db_time``; and
* discard the de-duplication set after each cycle. If a bug appears in a later
  cycle, fetch it again even when its ``last_change_time`` matches the value
  previously processed, because multiple changes can occur within the API's
  one-second timestamp precision.

Minimize requests and responses
-------------------------------

Request only the fields the integration uses by setting
:ref:`include_fields <rest-include-fields>`. This reduces response size and
server work. For polling searches, use
``include_fields=id,last_change_time`` and fetch the full bugs after all pages
have been collected.

Combine requests when possible. For example, request multiple bug IDs in one
call with ``GET /rest/bug?id=123,456`` instead of issuing one request per
bug. This search silently omits bugs that do not exist or that the caller cannot
see. Compare the returned IDs with the requested set and treat missing IDs as
not visible, not as deleted.

Whenever a search is paged with ``limit`` and ``offset``, pass a stable
``order`` such as ``order=bug_id``. Keep request URLs below the
:ref:`documented query-string size limit <rest-query-string-limit>`.

Write searches that survive configuration changes
--------------------------------------------------

Do not hard-code every open or closed status. Use ``status=__open__`` to search
all open bugs and ``status=__closed__`` to search all closed bugs. New workflow
statuses can then be added without breaking the integration.

Similarly, do not enumerate every resolution when searching for bugs that were
closed without being fixed. Use the custom-search parameters
``status=__closed__&f1=resolution&o1=notequals&v1=FIXED``. This allows new
non-fixed resolutions to be introduced without changing the integration.

When combining ``last_change_time`` with custom-search parameters, number the
``f<n>`` charts contiguously starting with ``f1``. Gaps in the numbering can
cause the generated change-time chart to replace an existing chart.
