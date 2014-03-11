cccb9
=====

A multiserver IRC bot
=======

(updates in progress as of 2014-03-11. Saving a partial version here because some help is better than none)

Getting Started
=======

cccb9 is a flexible multi-server IRC bot written in Ruby (1.9 or 2.0). To try it out, check out the code and run "./cccb9" from the root of the repo. This will generate a default profile and create some state directories. 

The bot is laid out as:
 
    cccb9*          - the bot start script
    conf/profiles/  - configuration profile directory
    conf/state/     - the default state directory
    lib/            - ... I won't insult your intelligence
    lib/cccb/core/  - the main module directory
    logs/           - the default log directory
    test/           - Some ancilliary test scripts
    web/template/   - templates for the internal web server

Generally, you start the bot with:

    $ ./cccb9 profile-name

If it doesn't already exist, the script will create a new profile named "default" in conf/profiles (creating any directories it needs to). Profiles are YAML, with the following layout: (this is a working example)

    :nick: name_for_the_bot
    :servers:
      freenode:
        :channels:
        - ! '#cccb9test'
        - ! '#cccb9dev'
        :host: irc.freenode.org
    :superuser_password: Some useful password that you set

Options that can be set in the profile are:
  * :logfile: (where to write the bot's logs)
  * :statefile: (where to store the statefiles)
  * :log_level: (set to ERROR, WARNING, INFO, VERBOSE, DEBUG or SPAM (in increasing order of outpout volume).
  * :nick: (the IRC nick of the bot)
  * :logfile_tag: (a tag to include on all lines logged, in case multiple instances use the same file)
  * :superuser_password: (A password that causes the bot to add a user to its list of superusers)
  * :servers: (A hash of any number of different servers to connect to. Each server can contain its own :nick:, a :host: and a :channels: array

Managing the Bot
=======

The bot is mostly configured via irc commands. The bot recognises requests in several differnet forms:

  * Any text sent directly to the bot ("/msg botname do something")
  * Channel text prefixed with the bot's nick ("/msg #channel botname: do soemthing" (or just "botname: do something" if you're in the channel)
  * If the (default enabled) option bang_commands_enabled is set, and channel text prefixed with an exclamation mark: ("/msg #channel !do something")

Configuration for the bot is based on a set of cascading storage dictionaries. These are defined by the bot and its modules to store configuration and session data. Each dictionary stores a number of keys which can be set to particular values. 

Dictionaries are stored in a tree structure:

    core                  
      \---> network  /- channels
      |           \--|
      |              \- users
      |
      \---> network  /- channels
                  \--|
                     \- users

  * core
    * This is a single global dictionary that provides default values for all the networks
    * All the dictionaries on the core object can only be altered by superusers
  * network
    * Each IRC network you connect the bot to has its own set of network dictionaries, where you can store per-network settings and data.
    * Network-level dictionaries inherit default values from the core.
    * Dictionaries on the network level can generally only be altered by superusers or by network admins. Each network has a "trusted" dictionary which can only be edited by superusers; adding the full address of a user there will make that user a network admin.
  * channels
    * Each channel has its own set of dictionaries which inherit from the network level (which may in turn inherit from the core). 
    * By default, keys in a channel-level dictionary may be set by superusers, network admins and channel operators.
  * users
    * Each user has their own set of dictionaries. When using commands in a channel, they may inherit defaults from the channel (depending on the command), but will always inherit from the network.
    * By default, each user has the ability to modify their own dictionaries freely, with the exceeption of a few security-related dictionaries.

Manipulating Dictionaries
========

The basic command to edit the dictionaries is "setting":

    18:47 <ccooke> !setting network::allowed_features
    18:47 <d20> ccooke: Setting freenode::allowed_features is set to 
    {"dice":true,"session":true,"public_log":true,"debug":true,"dice_set":true,"tables":true,"pom":true}

The setting command is used to both view and alter dictionaries. Generally, it uses a two or three part identifier for a dictionary or dictionary/key combination respectively. Some examples:

  * core::allowed_features - The entire set of all features loaded in the bot, along with their default enable or disable status. 
  * core::allowed_features::dice - The key that controls whether the dicebot code is enabled by default for all networks
  * network::allowed_features::dice - The key that controls whether the dicebot code is enabled for the current network
  * channel::allowed_features::dice - The same, but for the current channel (This form only works if used publicly, within a channel). There is no allowed_features dictionary on Users.
  * c(#cccb9test)::allowed_features::dice - The same, but referring to a specific channel by name
  * n(freenode)::allowed_features::dice - Referring to a specific network by name
  * u(ccooke)::options::timzeone - The timezone setting for the User 'ccooke'. 

To set a key, you send the request "setting <identifier> = <value>". For instance:

    18:54 <ccooke> !setting network::allowed_features::public_log = false
    18:54 <d20> ccooke: Setting freenode::allowed_features::public_log is set to false

To unset a key, assign either nil or an empty value to it.

Useful Dictionaries
=======

  * allowed_features
    * Enables and disables bot features in a specific context
  * options
    * Exists on core, network, channel and user objects
    * Stores toggles and values relevant to each object. Useful keys include:
      * bang_commands_enabled - enable and disable ! as a prefix for requests in channel
      * join_on_invite - whether the bot will automatically join a channel it is invited to. Set to false in a channel to prevent the bot joining that channel.
      * timezone - used to control the output of time values
