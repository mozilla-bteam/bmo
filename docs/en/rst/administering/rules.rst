.. _rules:

=============================================
Setting rules on creation and changes to bugs
=============================================

This is a Bugzilla extension that enables the creation and editing
of rules for editing fields in bugs.

Examples of these rules include:

* Only users in the editbugs group can set the Priority and Severity fields of a bug
* New bugs in the Localizations product must have the Due Date field set
* A bug in Core cannot be set to RESOLVED FIXED without an Assignee
* A bug in a particular product and component can’t be assigned a
  Priority without setting (Story) Points
* A user without editbugs can’t comment on a bug that’s resolved

A user with sufficient privileges, granted through group memberships,
could write rules in a structured language, submit them using an admin UI,
and enable the changes immediately.


This functionality is provided through the Rules extension in `/Extensions`.

.. _rules_writing:

Writing rules
=============

Users in a group with the can_administer_rules privilege can edit the rules for
a Bugzilla instance in the Administration screens.

Write rules using the `TOML format <https://github.com/toml-lang/toml>`_.

.. _example_rules:

Example rules
=============

.. code-block::

    # This will create an array of ‘rules’ in TOML
    [[rule]]
    # Prevent users who aren't in editbugs from setting priority
    name = "firefox priority"
    Error = "You cannot set the priority of a new bug."
    action = ["cannot_update","cannot_create"]
    [rule.filter]
        product = “Firefox”
    [rule.change]
        field = "priority"
    [rule.condition]
        not_user_group = "editbugs"
    [[rule]]
    # Prevent users who aren't in editbugs from assigning Firefox or Core bugs
    name = "firefox_assignee"
    Error = "You cannot assign this bug."
    action = ["cannot_update","cannot_create"]
    [rule.fitler]
        product = ["Firefox", "Core"]
    [rule.change]
        field = "assigned_to"
    [rule.condition]
        not_user_group = "editbugs"
    [[rule]]
    # Require canconfirm to mark a bug as FIXED
    name = "fixed canconfirm"
    Error = "You cannot mark this bug as FIXED"
    action = "cannot_update"
    [rule.change]
        field = "resolution"
        new_value = "FIXED"
    [rule.condition]
        not_user_group = "canconfirm"
    [[rule]]
    # people without editbugs can't comment on closed bugs
    name = "closed can comment"
    Error = "You cannot comment on closed bugs"
    action = "cannot_comment"
    [rule.condition]
        Bug_status = “RESOLVED”
        not_user_group = "editbugs"

.. _rules_properties:

Rules properties
================

A rule is composed of the following properties:

name
    The internal name of the rule.  Must be unique.

error
    Optional message displayed to a user when a rule is triggered.
    If `message` is not set or set to an empty value, the default
    Bugzilla permissions error will be displayed.

    Not currently implemented.

when
    When the rule is applied.

    *before*
        enforced in UI
    *after*
        enforced on save
    *both*
        enforced in UI and save (default)

    Not currently implemented.

action
    If the rule is activated (Filters) and the rules
    conditions are true, then the rule is applied.
    This property is mandatory for all rules.

    *cannot_update*
        don’t allow the changes to the bug to be saved
    *cannot_create*
        don’t allow the bug to be created
    *cannot_comment*
        don’t allow the comment on the bug

Note: if there are multiple rules which can apply
that result in the same action, if any of the rules
evaluate to true, then the action is applied.

For example: if there are two rules with an action of
cannot_save, but only one’s conditions are valid,
then cannot_save is still applied.

filter
    The filter section enumerates properties of a bug which
    must be TRUE for the action property (see below) to be enforced.

The available properties are:

    *product*
        a product name or array of product names
    *component*
        a component name or array of product names
    *field*
        the db name of a bug field such as ‘priority’ or ‘cf_status_firefox76’
    *value*
        the value of the field defined in field

If there are multiple filters, use the `[[rule.filter]]` syntax.

.. code-block::

    [[rule.filter]]
    [rule.filter]
        product = ["Core", "Toolkit"]
    [rule.filter]
        field = "type"
        value = "defect"

change
    The change section enumerates the changes to a bug’s fields
    which must be TRUE for the action to be enforced.

    *field*
        the db name of a bug field
    *new_value*
        the new value of the field, as set by the
        user editing the bug, required for the rule to be applied

condition
    The condition field ANDs together sub-properties that must
    evaluate to TRUE for the action property (see below) to be enforced.

    The sub-properties available are:

    *required_field*
        the db name of a bug field which must have an non-default value in order for the rule to be valid
    *all_user_group*
        a list of groups, each of which the user must be a member of, for the rule to be valid
    *any_user_group*
        a list of groups, at least one of which the user is a member of, for the rule to be valid
    *not_user_group*
        a group, if the user is not a member of, then the rule is applied
