=========================
BMO: bugzilla.mozilla.org
=========================

BMO is Mozilla's highly customized version of Bugzilla.

.. image:: https://circleci.com/gh/mozilla-bteam/bmo/tree/master.svg?style=svg
    :target: https://circleci.com/gh/mozilla-bteam/bmo/tree/master

.. contents::
..
    1  Using Vagrant (For Development)
      1.1  Setup Vagrant VMs
      1.2  Making Changes and Seeing them
      1.3  Technical Details
      1.4  Perl Shell (re.pl, repl)
    2  Docker Container
      2.1  Container Arguments
      2.2  Environmental Variables
      2.3  Persistent Data Volume

If you are looking to run Bugzilla, you should see
https://github.com/bugzilla/bugzilla.

If you want to contribute to BMO, you can fork this repo and get a local copy
of BMO running in a few minutes using Vagrant.

Using Vagrant (For Development)
===============================

You will need to install the following software:

* Vagrant 1.9.1 or later

Doing this on OSX can be accomplished with homebrew:

.. code-block:: bash

    brew install vagrant

For Ubuntu 16.04, download the vagrant .dpkg directly from
https://vagrantup.com.  The one that ships with Ubuntu is too old.

Setup Vagrant VMs
-----------------

From your BMO checkout run the following command:

.. code-block:: bash

    vagrant up

Depending on the speed of your computer and your Internet connection, this
will take from a few minutes to much longer.

If this fails, please file a bug `using this link <https://bugzilla.mozilla.org/enter_bug.cgi?assigned_to=nobody%40mozilla.org&bug_file_loc=http%3A%2F%2F&bug_ignored=0&bug_severity=normal&bug_status=NEW&cf_fx_iteration=---&cf_fx_points=---&component=Developer%20Box&contenttypemethod=autodetect&contenttypeselection=text%2Fplain&defined_groups=1&flag_type-254=X&flag_type-4=X&flag_type-607=X&flag_type-791=X&flag_type-800=X&flag_type-803=X&form_name=enter_bug&maketemplate=Remember%20values%20as%20bookmarkable%20template&op_sys=Unspecified&priority=--&product=bugzilla.mozilla.org&rep_platform=Unspecified&target_milestone=---&version=Production>`__.

Otherwise, you should have a working BMO developer machine!

To test it, you'll want to add an entry to /etc/hosts for bmo-web.vm pointing
to 192.168.3.43.

After that, you should be able to visit http://bmo-web.vm/ from your browser.
You can login as vagrant@bmo-web.vm with the password "vagrant01!" (without
quotes).

Making Changes and Seeing them
------------------------------

After editing files in the bmo directory, you will need to run

.. code-block:: bash

    vagrant rsync && vagrant provision --provision-with update

to see the changes applied to your vagrant VM. If the above command fails
or db is changed, do a full provision:

.. code-block:: bash

    vagrant rsync && vagrant provision

Technical Details
-----------------

This Vagrant environment is a very complete but scaled-down version of
production BMO.  It uses roughly the same RPMs (from CentOS 6, versus RHEL 6
in production) and the same perl dependencies (via
https://github.com/mozilla-bteam/carton-bundles).

It includes a couple example products, some fake users, and some of BMO's
real groups. Email is disabled for all users; however, it is safe to enable
email as the box is configured to send all email to the 'vagrant' user on the
web vm.

Most of the cron jobs and the jobqueue daemon are running.  It is also
configured to use memcached.

The push connector is not currently configured, nor is the Pulse publisher.


Perl Shell (re.pl, repl)
------------------------

Installed on the vagrant vm is also a program called re.pl.

re.pl an interactive perl shell (somtimes called a REPL (short for Read-Eval-Print-Loop)).
It loads Bugzilla.pm and you can call Bugzilla internal API methods from it, an example session is reproduced below:

.. code-block:: plain

   re.pl
   $ my $product = Bugzilla::Product->new({name => "Firefox"});
   Took 0.0262260437011719 seconds.

   $Bugzilla_Product1 = Bugzilla::Product=HASH(0x7e3c950);

   $ $product->name
   Took 0.000483036041259766 seconds.

   Firefox

It supports tab completion for file names, method names and so on. For more information see `Devel::REPL`_.

You can use the 'p' command (provided by `Data::Printer`_) to inspect variables as well.

.. code-block:: plain

  $ p @INC
  [
      [0]  ".",
      [1]  "lib",
      [2]  "local/lib/perl5/x86_64-linux-thread-multi",
      [3]  "local/lib/perl5",
      [4]  "/home/vagrant/perl/lib/perl5/x86_64-linux-thread-multi",
      [5]  "/home/vagrant/perl/lib/perl5",
      [6]  "/vagrant/local/lib/perl5/x86_64-linux-thread-multi",
      [7]  "/vagrant/local/lib/perl5",
      [8]  "/usr/local/lib64/perl5",
      [9]  "/usr/local/share/perl5",
      [10] "/usr/lib64/perl5/vendor_perl",
      [11] "/usr/share/perl5/vendor_perl",
      [12] "/usr/lib64/perl5",
      [13] "/usr/share/perl5",
      [14] sub { ... }
  ]

.. _`Devel::REPL`: https://metacpan.org/pod/Devel::REPL
.. _`Data::Printer`: https://metacpan.org/pod/Data::Printer

Docker Container
================

This repository is also a runnable docker container.

Container Arguments
-------------------

Currently, the entry point takes a single command argument.
This can be **httpd** or **shell**.

httpd
    This will start apache listening for connections on ``$PORT``
shell
    This will start an interactive shell in the container. Useful for debugging.


Environmental Variables
-----------------------

PORT
  This must be a value >= 1024. The httpd will listen on this port for incoming
  plain-text HTTP connections.
  Default: 8000

BUGZILLA_UNSAFE_AUTH_DELEGATION
  This should never be set in production. It allows auth delegation over http.

BMO_urlbase
  The public url for this instance. Note that if this begins with https://
  abd BMO_inbound_proxies is set to '*' Bugzilla will believe the connection to it
  is using SSL.

BMO_attachment_base
  This is the url for attachments.
  When the allow_attachment_display parameter is on, it is possible for a
  malicious attachment to steal your cookies or perform an attack on Bugzilla
  using your credentials.

  If you would like additional security on attachments to avoid this, set this
  parameter to an alternate URL for your Bugzilla that is not the same as
  urlbase or sslbase. That is, a different domain name that resolves to this
  exact same Bugzilla installation.

  For added security, you can insert %bugid% into the URL, which will be
  replaced with the ID of the current bug that the attachment is on, when you
  access an attachment. This will limit attachments to accessing only other
  attachments on the same bug. Remember, though, that all those possible domain
  names (such as 1234.your.domain.com) must point to this same Bugzilla
  instance.

BMO_db_driver
  What SQL database to use. Default is mysql. List of supported databases can be
  obtained by listing Bugzilla/DB directory - every module corresponds to one
  supported database and the name of the module (before ".pm") corresponds to a
  valid value for this variable.

BMO_db_host
  The DNS name or IP address of the host that the database server runs on.

BMO_db_name
  The name of the database.

BMO_db_user
  The database user to connect as.

BMO_db_pass
  The password for the user above.

BMO_site_wide_secret
  This secret key is used by your installation for the creation and
  validation of encrypted tokens. These tokens are used to implement
  security features in Bugzilla, to protect against certain types of attacks.
  It's very important that this key is kept secret.

BMO_inbound_proxies
  This is a list of IP addresses that we expect proxies to come from.
  This can be '*' if only the load balancer can connect to this container.
  Setting this to '*' means that BMO will trust the X-Forwarded-For header.

BMO_memcached_namespace
  The global namespace for the memcached servers.

BMO_memcached_servers
  A list of memcached servers (ip addresses or host names). Can be empty.

BMO_shadowdb
  The database name of the read-only database.

BMO_shadowdbhost
  The hotname or ip address of the read-only database.

BMO_shadowdbport
   The port of the read-only database.

BMO_apache_size_limit
  This is the max amount of unshared memory (in kb) that the apache process is
  allowed to use before Apache::SizeLimit kills it.

HTTPD_StartServers
  Sets the number of child server processes created on startup.
  As the number of processes is dynamically controlled depending on the load,
  there is usually little reason to adjust this parameter.
  Default: 8

HTTPD_MinSpareServers
  Sets the desired minimum number of idle child server processes. An idle
  process is one which is not handling a request. If there are fewer than
  MinSpareServers idle, then the parent process creates new children at a
  maximum rate of 1 per second.
  Default: 5

HTTPD_MaxSpareServers
  Sets the desired maximum number of idle child server processes. An idle
  process is one which is not handling a request. If there are more than
  MaxSpareServers idle, then the parent process will kill off the excess
  processes.
  Default: 20

HTTPD_MaxClients
  Sets the maximum number of child processes that will be launched to serve requests.
  Default: 256

HTTPD_ServerLimit
  Sets the maximum configured value for MaxClients for the lifetime of the
  Apache process.
  Default: 256

HTTPD_MaxRequestsPerChild
  Sets the limit on the number of requests that an individual child server
  process will handle. After MaxRequestsPerChild requests, the child process
  will die. If MaxRequestsPerChild is 0, then the process will never expire.
  Default: 4000

Persistent Data Volume
----------------------

This container expects /app/data to be a persistent, shared, writable directory
owned by uid 10001. This must be a shared (NFS/EFS/etc) volume between all
nodes.
