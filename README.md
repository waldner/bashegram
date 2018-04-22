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

# Repeat for each message type you want to handle
```

Each callback function is called with a single argument, which contains **the whole** update (ie, including the "ok" status field). A sample function to handle "message" updates might begin as follows:

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

## Utility functions

### Reply keyboard

If you want to send back a custom reply keyboard, you can use the `tg_create_reply_keyboard` function to create the JSON object from a list or array of arguments. Example:

```

# first two arguments are whether it's a one-time keyboard and whether it should be resized
# rest of arguments are the keys; use '|' to start a new line
tg_create_reply_keyboard true false foo bar "baz quu" '|' 4 5 6

# the kayboard is now in tg_lib['reply_keyboard']:
# {"keyboard":[["foo","bar","baz quu"],["4","5","6"]],"resize_keyboard":false,"one_time_keyboard":true}

tg_do_request sendMessage "chat_id=${chat_id}" "text=${text}" "reply_markup=${tg_lib['reply_keyboard']}"

```
