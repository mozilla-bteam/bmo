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
* For the payload url, enter ``https://bugzilla.mozilla.org/rest/github/pull_request``.
* Choose ``application/json`` for the content type.
* You will need to enter the signature secret obtained from a BMO admin (DO NOT SHARE).
* Make sure Enable SSL is turned on.
* Select "Let me select individual events" and only enable changes for "Pull Requests".
* Make sure at the bottom that "Active" is checked on.
* Save the webhook.

Note: Past pull requests will not automatically get a link created in the bug. New pull
requests should get the link automatically when the pull request is first created.

Additional Note: The API endpoint looks at the pull request title for the bug id so
make sure the title is formatted correctly to allow the bug id to be determined.
Examples are: ``Bug 1234:``, ``Bug - 1234``, ``bug 1234``, or ``Bug 1234 -``.

**Request**

The endpoint will error for any requests that do not have ``X-GitHub-Event`` header with
either the value ``pull_request`` or ``ping``. Ping events can happen when a webhook is
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

Operation was completed successfully.

.. code-block:: js

   {
     "error": 0
     "id": 22
   }

=======  =======  ===================================================
name     type     description
=======  =======  ===================================================
error    boolean  Whether the operation was successful or not.
id       int      ID of the pre-existing or newly-created attachment.
=======  =======  ===================================================

An error condition occurred.

.. code-block:: js

   {
     "error": 1
     "message": "The pull request title did not contain a valid bug ID."
   }

=======  =======  ===================================================
name     type     description
=======  =======  ===================================================
error    boolean  Whether the operation was successful or not.
message  string   A message detailing what the error condition was.
=======  =======  ===================================================

Push Comments
-------------

This API endpoint is for adding comments to a bug when a push is made to a linked
Github repository. The comment will be short and specially formatted using pieces
of information from the full JSON sent to Bugzilla by the push event. If the bug
does not have the keyword ``leave-open`` set, the bug will be resolved as FIXED.
Also, the ``qe-verity`` flag will be set to `+` for the bug. For some specific 
repositories, a Firefox status flag may be set to FIXED.

**Github Setup Instructions**

* From the repository main page, click on the Settings tab.
* Click on Webhooks from the left side menu.
* Click on the Add Webhook button near the top right.
* For the payload url, enter ``https://bugzilla.mozilla.org/rest/github/push_comment``.
* Choose ``application/json`` for the content type.
* You will need to enter the signature secret obtained from a BMO admin (DO NOT SHARE).
* Make sure Enable SSL is turned on.
* Select "Let me select individual events" and only enable changes for "Pushes".
* Make sure at the bottom that "Active" is checked on.
* Save the webhook.

Additional Note: The API endpoint looks at the commit messages for the bug ID so
make sure the message is formatted correctly to allow the bug ID to be determined.
Examples are: ``Bug 1234:``, ``Bug - 1234``, ``bug 1234``, or ``Bug 1234 -``.

**Request**

The endpoint will error for any events that do not have ``X-GitHub-Event`` header with
either the value ``push`` or ``ping``. Ping events can happen when a webhook is first
created. In that case, Bugzilla will return success if the signature checks out.

.. code-block:: text

   POST /rest/github/push_comment

.. code-block:: js

  {
    "ref": "refs/heads/master",
    "repository": {
      "full_name": "mozilla-bteam/bmo",
      "html_url": "https://github.com/mozilla-bteam/bmo",
      "description": "bugzilla.mozilla.org source - report issues here: https://bugzilla.mozilla.org/enter_bug.cgi?product=bugzilla.mozilla.org",
    },
    "commits": [
      {
        "message": "Bug 1803939 - Webhook URL field is too short",
        "url": "https://github.com/mozilla-bteam/bmo/commit/b4edfe9343e1474e0a6959531d2362078ea6ee84",
        "author": {
          "name": "dklawren",
          "username": "dklawren"
        },
        "added": [],
        "removed": [],
        "modified": [
          "extensions/Webhooks/Extension.pm",
          "extensions/Webhooks/template/en/default/account/prefs/webhooks.html.tmpl"
        ]
      }
    ]
  }

The above example is only a small amount of the full data that is sent.

Note: Only the first line of the commit message will be used on the bug comment.

Some params must be set, or an error will be thrown. The required params are
marked in **bold**.

===================================  =======  =======================================================================
name                                 type     description
===================================  =======  =======================================================================
**ref**                              string   The branch (ref) that the commit was pushed to (ex: refs/heads/master).
**repository.full_name**             string   The name of the Github repository.
**commits**                          array    An array of commit objects that were pushed.
**commits.<index>.message**          string   The full commit message containing the bug report ID.
**commits.<index>.url**              string   The full URL to the commit on Github.
**commits.<index>.author.username**  string   The user name of the commit author.
===================================  =======  =======================================================================

**Response**

Operation was completed successfully.

.. code-block:: js

  {
    "bugs": {
      1803939: [
        {
          "text": "Authored by https:\/\/github.com\/dklawren\nhttps:\/\/github.com\/mozilla-bteam\/bmo\/commit\/4ef4caed5bc22a734bd9ec15aaac87c19ef6e80e\nBug 1803939 - Webhook URL field is too short"
        }
      ]
    },
    "error": 0
  }

======================  =======  ========================================================
name                    type     description
======================  =======  ========================================================
error                   boolean  Whether the operation was successful or not.
bugs                    object   Object containing bug IDs as object keys.
bugs.<id>               array    List of comment objects that were added to the bug <id>.
bugs.<id>.<index>.text  string   The comment text that was added to the bug <id>.
======================  =======  ========================================================

An error condition occurred.

.. code-block:: js

   {
     "error": 1
     "message": "The push commit message did not contain a valid bug ID."
   }

=======  =======  ===================================================
name     type     description
=======  =======  ===================================================
error    boolean  Whether the operation was successful or not.
message  string   A message detailing what the error condition was.
=======  =======  ===================================================
