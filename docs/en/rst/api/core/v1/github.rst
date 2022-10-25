Github
============

Pull Requests
-------------

This API endpoint is for creating attachments in a bug that are redirect links to a
specific Github pull request. This allows a bug viewer to click on the Github link
and be automatically redirected to the pull request.

**Github Setup Instructions**

* From the repository main page, click on the Settings tab.
* Click on Webhooks from the left side menu.
* Click on the Add Webhook button near the top right.
* For the payload url, enter `https://bugzilla.mozilla.org/rest/github/pull_request`.
* Choose `application/json` for the content type.
* You will need to enter the signature secret obtained from a BMO admin (DO NOT SHARE).
* Make sure Enable SSL is turned on.
* Select "Let me select individual events" and only enable changes for "Pull Requests".
* Make sure at the bottom that "Active" is checked on.
* Save the webhook.

Note: Past pull requests will not automatically get a link created in the bug unless an
edit event occurs on those older pull requests at some point. New pull requests should
get the link automatically when the pull request is first created.

Additional Note: The API endpoint looks at the pull request title for the bug id so
make sure the title is formatted correctly to allow the bug id to be determined.

**Request**

The endpoint will error for any requests that do not have `X-GitHub-Event` header with
either the value `pull_request` or `ping`. Ping events can happen when a webhook is
first created. In that case, Bugzilla will return success if the signature checks out.

.. code-block:: text

   POST /rest/github/pull_request

.. code-block:: js

   {
     "pull_request": {
       "html_url": "https://github.com/mozilla-bteam/bmo/pull/1943",
       "number": 1943,
       "title": "Bug 1234567 - Some really bad bug which should be fixed"
     }
   }

The above example is only a small amount of the full data that is sent.

Some params must be set, or an error will be thrown. The required params are
marked in **bold**.

=========================  =======  =======================================================
name                       type     description
=========================  =======  =======================================================
**pull_request**           Object   Object containing data about the current pull request.
**pull_request.html_url**  string   A fully qualified link to the pull request.
**pull_request.number**    int      The pull request ID unique to the repository.
**pull_request.title**     string   The full title of the current pull request containing
                                    the bug report ID.
=========================  =======  =======================================================

**Response**

.. code-block:: js

   {
     "id": 22
   }

====  ====  ===================================================
name  type  description
====  ====  ===================================================
id    int   ID of the pre-existing or newly-created attachment.
====  ====  ===================================================
