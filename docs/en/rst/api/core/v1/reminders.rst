Reminders
=========

This part of the Bugzilla API allows creating, listing, and removing of Bugzilla reminders.

.. _rest_get_reminder:

Get Reminder
------------

This allows you to retrieve information about a specific reminder.

**Request**

.. code-block:: text

   GET /rest/reminder/123

**Response**

.. code-block:: js

  {
    "id": 123,
    "bug_id": 456,
    "note": "This is a reminder note",
    "reminder_ts": "2024-06-08",
    "creation_ts": "2024-06-07",
    "sent": false
  }

.. _rest_reminder_object:

Reminder Object

========================  =======  ========================================================
name                      type     description
========================  =======  ========================================================
id                        int      An integer ID uniquely identifying the reminder in
                                   this installation only.
bug_id                    int      Bug ID associated with the reminder.
note                      string   A descriptive note associated with the reminder.
reminder_ts               date     The date when the reminder will be sent out.
creation_ts               date     The date when the reminder was originally created.
sent                      boolean  A boolean value that is set to true when delivered.
========================  =======  ========================================================

.. _rest_reminder_create:

Create Reminder
---------------

This allows you to create a new reminder associated with a specific bug in Bugzilla.

**Request**

To create a new reminder:

.. code-block:: text

  {
    "bug_id": 456,
    "note" : "This is a reminder note",
    "reminder_ts" : "2024-06-08"
  }

========================  ======  =================================================================
name                      type    description
========================  ======  =================================================================
bug_id                    int      Bug ID associated with the reminder.
note                      string   A descriptive note associated with the reminder.
reminder_ts               date     The date when the reminder will be sent out.
========================  ======  =================================================================

**Response**

.. code-block:: js

  {
    "id": 123,
    "bug_id": 456,
    "note": "This is a reminder note",
    "reminder_ts": "2024-06-08",
    "creation_ts": "2024-06-07",
    "sent": false
  }

A reminder object `rest_reminder_object`_ is returned.

.. _rest_reminder_remove:

Remove Reminder
---------------

This allows you to remove an existing reminder in Bugzilla.

**Request**

.. code-block:: text

   DELETE /rest/reminder/123

**Response**

If the removal of the reminder was successful, it should look like:

.. code-block:: js

   {
     "success": 1
   }
