export moonscript = require "moonscript.base"
export http = require "socket.http"
export https = require "ssl.https"
export URL = require "socket.url"
export ltn12 = require "ltn12"
--export serpent = require "serpent"
export socket = require "socket"
export JSON = require "cjson"
export colors = require 'ansicolors'
export config = moonscript.loadfile "config.moon",implicitly_return_root:true
utilities = moonscript.loadfile "utilities.moon",implicitly_return_root:true
utilities!
export redis = (Redis @).client
export plugins = {}

export bot_run = class bot_run
  @admins_ids: config!.admins
  print_admins: =>
    for k,v in pairs (config!.admins)
      print( colors "%{black whitebg}#{v}%{reset}%{bright green} Added as admin%{reset}")

  print_info: =>
    info = telegram!\getMe!
    export bot_username = info.result.username
    export bot_first_name = info.result.first_name
    export bot_id = info.result.id
    print colors("%{bright red}@#{info.result.username}
#{info.result.first_name}
#{info.result.id}%{reset}
")

  plugins_load: =>
    print "\n"
    for k,v in pairs config!.plugs
      pcall(->
        t = moonscript.loadfile "plugins/#{v}.moon",implicitly_return_root:true
        plugins[v] = t
      )
      print(colors "Plugin %{black whitebg}#{v}%{reset} loaded")
  Bot_loading: =>
    export last_update = last_update or tonumber(redis\get "bot:update_id") or 0

    export last_cron = last_cron or os.time!

    export is_running = true


  new: =>
    @print_info!
    @print_admins!
    @plugins_load!
    @Bot_loading!


export match_plugin = (plugin, plugin_name, msg) ->
  for k, patterns in pairs (plugin @).patterns
    matches = match_trigger patterns, msg.text
    print "plugin #{plugin_name} triggered: #{patterns}" if matches
    if matches
      if redis\get "bot:plugin_disabled_on_chat:#{plugin_name}:#{msg.chat.id}"--Check if plugin is disabled on chat or not
        unless is_admin(msg)
          return
      --plugin status
      redis\incr "bot:plugin_usage:#{plugin_name}"
      redis\incr "bot:plugin_usage_on_chat:#{plugin_name}:#{msg.chat.id}"
      redis\incr "bot:plugins_usage"
      redis\incr "bot:plugins_usage_on_chat:#{msg.chat.id}"
      result = (plugin @).run msg, matches
      if result
        telegram!\sendChatAction msg.chat.id, "typing"
        if msg.chat.type ~= "private"
          telegram!\sendMessage msg.chat.id, result, msg.message_id, "Markdown", true
        else
          telegram!\sendMessage msg.chat.id, result, false, "Markdown", true


export msg_processor = (msg) ->
  if msg.text
    msg.text = msg.text\gsub "@#{bot_username}",""--Remove username
  msg_text = msg.text or ""
  --User changed chat name
  msg_text = "changed group name to > #{msg.new_chat_title}" if msg.new_chat_title
  --User changed chat photo
  msg_text = "changed group photo" if msg.new_chat_photo
  --User changed chat photo
  msg_text = "Deleted group photo" if msg.delete_chat_photo
  --User created chat
  msg_text = "Created chat group" if msg.group_chat_created
  --Supergroup created
  msg_text = "Created super group" if msg.supergroup_chat_created
  --Chat migrated
  msg_text = "chat migrated from #{msg.migrate_from_chat_id} To #{msg.migrate_to_chat_id}" if msg.migrate_to_chat_id and msg.migrate_from_chat_id
  --Channel created
  msg_text = "Created channel" if msg.channel_chat_created
  --User added someone
  msg_text = "added #{msg.new_chat_participant.first_name} [#{msg.new_chat_participant.id}]" if msg.new_chat_participant
  --User removed someone
  msg_text = "removed #{msg.left_chat_participant.first_name} [#{msg.left_chat_participant.id}]" if msg.left_chat_participant
  --System full time and date
  date = os.date "[ %X ]  "
  --Chat type (group,supergroup,private)
  chat_type = "NULL"
  chat_type = "Group" if msg.chat.type == "group"
  chat_type = "Supergroup" if msg.chat.type == "supergroup"
  chat_type = "Private" if msg.chat.type == "private"
  user_info = user_info msg.from
  text = ""
  if tostring(msg.chat.type) == "group" or tostring(msg.chat.type) == "supergroup"
    text = "

%{red}#{date}%{reset} %{green}#{user_info}%{reset} %{yellow}#{msg.chat.title} [#{msg.chat.id}]%{reset} %{magenta}#{chat_type}%{reset}

%{bright blue}#{msg_text}%{reset}"
  elseif tostring(msg.chat.type) == "private"
    text = "

%{red}#{date}%{reset} %{green}#{user_info}%{reset} %{magenta}#{chat_type}%{reset}

%{bright blue}#{msg_text}%{reset}"
  else
    text = ""

  print(colors text)--print messages

--msg statistics,nickname,fowarded msgs,blacklist

  nickname = redis\get("nickname:"..msg.from.id)
  if nickname
    msg.from.real_first_name = msg.from.first_name
    msg.from.real_last_name = msg.from.last_name if msg.from.last_name
    msg.from.first_name = "#{nickname}"
    msg.from.last_name = " "

  if msg.date < os.time! - 30--Ignore old messages
    return
  --Return about text if someone added bot to chat
  msg.text = "/about" if msg.new_chat_participant and msg.new_chat_participant.id == bot_id

  if msg.new_chat_participant and msg.new_chat_participant.id ~= bot_id--Say hi to new members
    msg.from = msg.new_chat_participant
    msg.text = "Hi #{bot_first_name\lower!}"

  if msg.left_chat_participant--Say bye to users who leave
    msg.from = msg.left_chat_participant
    msg.text = "bye jack"

  if msg.forward_from--Will send info about the user you fowarded his/her msg to bots private
    if msg.chat.type == "private"
      msg.from = msg.forward_from
      msg.text = "/who"
    else
      return

  if msg.chat.type == "private" and msg.text--If msg is not a command in private will talk to user
    if not msg.text\match '^[/!]'
      msg.text = "#{bot_first_name\lower!}, #{msg.text}"

  if msg.text
    if msg.chat.type == "group" or msg.chat.type == "supergroup"--Same as above but in groups and supergroups also user should replyed to bots msg
      if not msg.text\match('^[/!]') and msg.reply_to_message and msg.reply_to_message.from.id == bot_id
        msg.text = "#{bot_first_name\lower!}, #{msg.text}"

  is_blacklisted = redis\sismember "bot:blacklist",msg.from.id--Ignore banned/blacklisted users
  if is_blacklisted and not is_admin msg--Admins wont be ignored even if they are blacklisted
    return

  if msg.chat.type == "channel"--Ignore channels
    return


  --Add the chat id to database
  redis\sadd "bot:chats",msg.chat.id
  redis\sadd "bot:privates",msg.chat.id if msg.chat.type == "private"
  redis\sadd "bot:groups",msg.chat.id if msg.chat.type == "group"
  redis\sadd "bot:supergroups",msg.chat.id if msg.chat.type == "supergroup"

  --Add chat/user info to database

  --user
  redis\hset "bot:users:#{msg.from.id}","first_name",msg.from.first_name
  redis\hset "bot:users:#{msg.from.id}","last_name",msg.from.last_name if msg.from.last_name
  redis\hset "bot:users:#{msg.from.id}","username",msg.from.username if msg.from.username

  --chats
  if msg.chat.type ~= "private"
    redis\hset "bot:chats:#{msg.chat.id}","title",msg.chat.title
    redis\hset "bot:chats:#{msg.chat.id}","type",msg.chat.type


  --Group memebers
  if msg.chat.type ~= "private"
    redis\sadd "bot:chat#{msg.chat.id}",msg.from.id

  --msg statistics
  redis\incr "bot:total_messages"
  redis\incr "bot:total_user_msgs_in_private:#{msg.from.id}" if msg.chat.type == "private"
  redis\incr "bot:total_chat_msgs:#{msg.chat.id}" if msg.chat.type ~= "private"
  redis\incr "bot:total_users_msgs_in_chat:#{msg.chat.id}:#{msg.from.id}" if msg.chat.type ~= "private"

  for name, plugin in pairs plugins--Go over plugins and check patterns for match
    match_plugin(plugin, name, msg)


bot_run!--Load the bot

while is_running--A loop for getting messages

  if last_cron < os.time() - 10--cron thing
    for i,v in pairs plugins
      if (v @).cron
        pcall(->
          v.cron!
        )


  res = telegram!\getUpdates last_update + 1
  if res
    for i,msg in ipairs res.result
      msg_processor msg.message
      export last_update = msg.update_id
      redis\set "bot:update_id", msg.update_id
  else
    print "Connection failed"
