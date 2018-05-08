# bashegram

Bash framework to create Telegram bots

### What's this? (besides being the worst-named package of all times, that is)

This is a Bash library to create [Telegram bots](https://core.telegram.org/bots/api). Source the library, define a few functions, and you're ready to go. The only requirements are **[bash](https://www.gnu.org/software/bash/)** (version >= 4.3), **[curl](https://curl.haxx.se/)**, **[jq](https://stedolan.github.io/jq/)** and **awk** (any version should work).

## Installation

No special installation needed. Just put **`bashegram.sh`** wherever you want. You have to know the location because you'll have to source it in your script.

## Getting started

- Create a bot following [the instructions](https://core.telegram.org/bots#3-how-do-i-create-a-bot). Note down the unique authorization token that is generated for your bot.

- Source `bashegram.sh` in your script.

- Implement a function called `tg_get_userdef_credentials` that sets some environment variables with suitable values (`tg_lib['bot_token']` using the bot token you obtained in the first step). See the sample bot script for an example.

- Call `tg_api_init` and check that it returns without errors.

- (Optional) Define [filters](#update-filters) (by message type or sending user)

- Define and implement [callback functions](#callback-functions) for the update types you want to manage with your bot

- Call `tg_bot_main_loop` and let the library dispatch message to your callback function(s).

## Logging

Sourcing the library gives access to a rudimentary log function called `tg_log`. Its arguments are a log level (one of  DEBUG, INFO, NOTICE, WARNING, ERROR) and the message to log. You can use this function to log your bot's messages together with those coming from the library. By default, the library detects automatically whether to log to file or to stdout (if stdout is not a terminal, log to file; otherwise log to stdout). The log destination can however be forced. The minimum logging level can also be configured, or logging can be turned off altogether. See code below for examples.

## Internals

All internal variables used by the library are contained in a few bash associative arrays, the main one being `tg_lib[]`.

After each API function invocation (ie, after calling `tg_do_request`), the three variables `tg_lib['last_http_headers']`, `tg_lib['last_http_body']` and `tg_lib['last_http_code']` contain what their name says, so they can be inspected in your code for extra control.

Each time `tg_do_request` is callled, some basic argument checks are performed, then `tg_do_curl` is called to do the actual API call.

## Sample code

See the included [`simplebot.sh`](https://github.com/waldner/bashegram/blob/master/simplebot.sh) script for a bot that responds to some basic commands and inline queries (NOTE: inline queries must be enabled for the bot for them to work). Send `/help` to the bot to have a summary of its commands.

That is a very simplistic example, in practice a real bot will likely use some kind of persistent storage backend to store messages and/or configuration.

### Calling the API

To call API methods, use the `tg_do_request` function. The first argument is the method name (eg, `sendMessage`, `answerInlineQuery` etc. - _case insensitive_), followed by the method's arguments in **`key=value`** form (at least mandatory ones must be present, they are checked). For methods that can read a local file (eg `sendPhoto`, `sendVideo` etc), you must prefix the file name with a **`@`** so the library knows it's a local file and can check for its existence and arrange for it to be read.

Examples:

```
# send a message
tg_do_request sendMessage "chat_id=12345" "text=Hello, world!"

# send a photo from local file
tg_do_request sendPhoto "chat_id=12345" "photo=@/tmp/photo.jpg" "caption=A nice picture"

# send a photo from URL
tg_do_request sendPhoto "chat_id=12345" "photo=http://example.com/photo.jpg" "caption=A nice picture"

# answer an inline query with two photos
tg_do_request answerInlineQuery "inline_query_id=12345" 'results=[{"type":"photo","id":"1","photo_url":"http://example.com/1.jpg","thumb_url":"http://example.com/thumb/1.jpg"},{"type":"photo","id":"2","photo_url":"http://example.com/2.jpg","thumb_url":"http://example.com/thumb/2.jpg"}]'

```

## Update filters

By default, _all update types from any user are delivered to the bot_. You may want to handle only certain kind of updates (eg, inline queries only) and/or restrict valid senders to a limited set of users. 

### Filter by update type

Sample code to apply filtering by update type:

```
# disallow only inline queries
tg_update_filter_disallow inline_query

#---------------------------------------------

# allow only messages and inline queries
declare -a allowed_types=( message edited_message inline_query )
declare -a disallowed_types=( channel_post edited_channel_post chosen_inline_result callback_query shipping_query pre_checkout_query )

tg_update_filter_disallow "${disallowed_types[@]}"

# optional, everything not explicitly disallowed is allowed anyway
tg_update_filter_allow "${allowed_types[@]}"

#---------------------------------------------

# allow only messages and inline queries, alternative way

# NOTE: the following sets allowed_updates=[] which means "receive everything",
# so it's mandatory to explicitly allow something later for the filter to be meaningful
tg_update_filter_disallow "*"

# mandatory: explicitly allow messages and inline queries
tg_update_filter_allow message edited_message inline_query

```

### Filter by sender

**NOTE:** This filter applies only to updates of type `message` or `edited_message`, which have a real sender (as opposed to, say, channel posts).
Sample code to apply filtering by sender (user ID or username):

```
# block a specific user
tg_sender_disallow "@blockeduser"    # other users are allowed

#---------------------------------------------

# allow only two users

tg_sender_disallow "*"
tg_sender_allow "123456789" "@johndoe"

```

## JSON object management

Since the API uses JSON as the message format, the library provides helper functions to work with JSON messages.
(Of course, you can also do JSON parsing entirely on your own if you like.)

### Parsing a JSON object

If you have a JSON object in a string, you can call `tg_parse_object` to have it parsed and its values assigned to an associative array of your choice, whose keys are the JSON paths of each JSOn element.

Example: suppose you have the following JSON object (for example, a message received by the bot):

```
# this is in a bash variable called "$json"
{
  "update_id": 52183554,
  "message": {
    "message_id": 208,
    "from": {
      "id": 123456789,
      "is_bot": false,
      "first_name": "John",
      "last_name": "Doe"
    },
    "chat": {
      "id": 123456789,
      "first_name": "John",
      "last_name": "Doe",
      "type": "private"
    },
    "date": 1524401395,
    "text": "/start",
    "entities": [
      {
        "offset": 0,
        "length": 6,
        "type": "bot_command"
      }
    ]
  }
}
```

You can do the following:

```
declare -A message_object
tg_parse_object message_object "$json"

```

and have the following result (obtained with `tg_dump_object message_object`):

```
message_object['message.text']="/start"
message_object['message.chat.id']="123456789"
message_object['message.chat']="{"id":123456789,"first_name":"John","last_name":"Doe","type":"private"}"
message_object['message.entities.0.type']="bot_command"
message_object['message.from.last_name']="Doe"
message_object['message.message_id']="208"
message_object['message.date']="1524401395"
message_object['message.from.is_bot']="false"
message_object['message.entities.0.offset']="0"
message_object['message.chat.type']="private"
message_object['message.entities.0']="{"offset":0,"length":6,"type":"bot_command"}"
message_object['message.from']="{"id":123456789,"is_bot":false,"first_name":"John","last_name":"Doe"}"
message_object['message.entities']="[{"offset":0,"length":6,"type":"bot_command"}]"
message_object['message.from.id']="123456789"
message_object['message.chat.last_name']="Doe"
message_object['message.from.first_name']="John"
message_object['message.entities.0.length']="6"
message_object['message']="{"message_id":208,"from":{"id":123456789,"is_bot":false,"first_name":"John","last_name":"Doe"},"chat":{"id":123456789,"first_name":"John","last_name":"Doe","type":"private"},"date":1524401395,"text":"/start","entities":[{"offset":0,"length":6,"type":"bot_command"}]}"
message_object['update_id']="52183554"
message_object['message.chat.first_name']="John"
```

So all object keys can be accessed, either leaf nodes, arrays or sub-objects. The associative array keys are the JSON paths of the corresponding elements.

Arrays can be accessed as follows:

```
# message_object['message.entities'] is an array (if present), so

if tg_array_has_key message_object "message.entities"; then
  index=0   # array index

  while tg_array_has_key message_object "message.entities.${index}"; do

    offset=${message_object["message.entities.${index}.offset"]}
    length=${message_object["message.entities.${index}.length"]}
    type=${message_object["message.entities.${index}.type"]}

    # ...

    ((index++))
  done
fi

```

### Creating JSON objects

The `tg_create_object` function can be used to go the other way round, creating a JSON object string starting from an associative array, whose keys are the (dot-separated) JSON paths of the to-be-created JSON object. Example:

```
declare -A inline_query_results=()
inline_query_results['0.type']="photo"
inline_query_results['0.id']="12345"
inline_query_results['0.photo_url']="http://my.photos.com/12345"
inline_query_results['0.thumb_url']="http://my.photos.com/thumb/12345"
inline_query_results['1.type']="photo"
inline_query_results['1.id']="12347"
inline_query_results['1.photo_url']="http://my.photos.com/12347"
inline_query_results['1.thumb_url']="http://my.photos.com/thumb/12347"

results_json=$(tg_create_object inline_query_results)

# $results_json now is:
#[
#  {
#    "thumb_url": "http://my.photos.com/thumb/12345",
#    "photo_url": "http://my.photos.com/12345",
#    "type": "photo",
#    "id": 12345
#  },
#  {
#    "type": "photo",
#    "photo_url": "http://my.photos.com/12347",
#    "thumb_url": "http://my.photos.com/thumb/12347",
#    "id": 12347
#  }
#]


tg_do_request answerInlineQuery "inline_query_id=${inline_query_id}" "results=${results_json}"

# etc...

```

Note that whenever numeric components are detected in the key (eg like "0.*", "1.*" above), those are treated as _numbers_ in the resulting JSON path, so an array is created (as opposite to an object key). Since the JSON objects used in the Telegram bot API have only alphanumeric keys, this is an attempt to behave sensibly without complicating life too much for the user.

## Callback functions

Add a callback function (it must exist) with the following code:

```
process_message(){
  # ...
  # manage a message
}

process_inline_query(){
  # ...
  # manage an inline query
}

# ...

tg_set_callback "message" process_message || { tg_log ERROR "Failed to set callback for 'message', terminating" && exit 1; }
tg_set_callback "inline_query" process_inline_query || { tg_log ERROR "Failed to set callback for 'inline_query', terminating" && exit 1; }

# Repeat for each update type you want to handle
```

Each callback function is called with a single argument, which contains **the whole** update (ie, including the top-level "ok" and "result" fields). A sample function to handle "message" updates might begin as follows:

```
process_message(){

  local update=$1

  local -A message_obj update_obj

  tg_parse_object update_obj "$update"

  # here you can check ${update_obj[ok]}, although it's checked before dispatching

  # extract the actual message
  tg_parse_object message_obj "${update_obj['message']}"

  # now message_obj has its keys populated with the message fields

  local message_id=${message_obj[message_id]}
  local text=${message_obj[text]}

  local chat_id=${message_obj[chat.id]}

  # do something with $text and/or $chat_id ...
  # ...

```

### Periodic callback

In addition to the callbacks that manage specific update types (described above), it's possible to supply a so-called _periodic callback_, which is simply a function that gets called, well, periodically during the bot's main loop. The given function will be called at most once per polling interval. Every time the main loop returns from the **`getMessages`** call (which lasts at most the polling interval time), it checks whether it's time to call the perioduc callback (if one is defined), and if so, it calls it.

The periodic callback function can be useful if the bot has to do some sort of external activity and/or send messages or notifications to a chat that are not in response to commands.

Of course, while the periodic callback runs the bot won't be able to respond to commands, so this has to be kept in mind if the function takes a long time to run.

This is an example periodic callback function that checks whether some event has occurred and sends a notification to a channel (note that the bot must be a channel administrator to do this):

```
check_event(){

  local channel_id="12345678"   # where to send our notifications

  local event

  event=$(command to check event)

  if [ "$event" != "" ]; then
    tg_do_request sendMessage "chat_id=${channel_id}" "text=Event happened: $event"
  fi
}

...

# optional
tg_set_long_polling_timeout 30

# now "check_event" will be called roughly every 30 seconds
tg_set_periodic_callback check_event

...

tg_bot_main_loop

```

### Advanced usage

If the periodic callback function or the main loop logic provided by the library are not enough for your needs, you can directly call the specific library functions that check for new messages and dispatch them. Here are the available functions:

* **`tg_get_maybe_updates`**: this function calls the actual `getUpdates` API and takes a single argument: the polling timeout. If updates are available, they are added to an internal update queue and the update offset is updated.

* **`tg_queue_has_updates`**: use this function to check whether there are updates in the update queue.

* **`tg_get_first_update`**: If there are queued updates, it returns the first update in the queue.

* **`tg_get_queue_length`**: returns the current number of updates in the queue.

* **`tg_dequeue_update`**: removes the first queued update from the update queue.

* **`tg_dispatch_updates`**: this function checks whether there are queued messages, determine their types, dequeue them and dispatches them to the corresponding user callback function for the specific type (if one is available). The function takes a single argument which can be `0` or `1`: if it's `1`, the function also performs sender filter checks (where applicable) and does not dispatch a message if its sender is not authorized; if it's `0`, all messages are dispatched, without checks.

* **`tg_dispatch_update`**: this function dispatches a single update, and needs two arguments: the actual update, and the update type. If a callback exists for the update type, it is called passing the update as argument.

## Utility functions

### Reply keyboard

If you want to send back a custom reply keyboard, you can use the `tg_create_reply_keyboard` function to create the JSON object from a list or array of arguments. Example:

```
# first two arguments are whether it's a one-time keyboard and whether it should be resized
# rest of arguments are the keys; use '|' to start a new line
keyboard=$(tg_create_reply_keyboard true false foo bar "baz quu" '|' 4 5 6)

# the keyboard is now in ${keyboard}:
# {"keyboard":[["foo","bar","baz quu"],["4","5","6"]],"resize_keyboard":false,"one_time_keyboard":true}

tg_do_request sendMessage "chat_id=${chat_id}" "text=${text}" "reply_markup=${keyboard}"

```

