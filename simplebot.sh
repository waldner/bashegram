#!/bin/bash

# Very simple Telegram bot using bashegram

# edit to use your actual value here
tg_get_userdef_credentials(){
  tg_lib['bot_token']="111111111zzzzzzzzzzzzzzzzzzzzzxxxxxxxxxxxxxxxxxx"
}

########################## callback functions ####################

# process a "message" update
process_message(){

  local update=$1

  local -A message_obj update_obj

  tg_parse_object update_obj "$update"
  tg_parse_object message_obj "${update_obj[message]}"

  # now message_obj contains the message

  local message_id=${message_obj[message_id]}
  local text=${message_obj[text]}

  local chat_id=${message_obj[chat.id]}
  local sender=${message_obj[from.first_name]}

  # check whether it's a command
  if [[ "$text" =~ ^/ ]]; then

    # remove bot name at the end, if present
    text=${text%@"${tg_lib['bot_username']}"}

    case "$text" in

      /start)
        tg_do_request sendMessage "chat_id=${chat_id}" "text=Hello $sender, this is ${tg_lib['bot_name']}"
        ;;

      /help)
        tg_do_request sendMessage "chat_id=${chat_id}" "text=Following commands are available: '/start', '/echo <text>', '/getphoto <path>', '/keyboard'"
        ;;

      /settings)
        tg_do_request sendMessage "chat_id=${chat_id}" "text='$text' not implemented"
        ;;

      /echo\ *)
        # echo the message back
        local msg="${text#/echo }"
        tg_do_request sendMessage "chat_id=${chat_id}" "text=$msg"
        ;;

      /keyboard)
        # send a custom keyboard until user says stop
        local keyboard=$(tg_create_reply_keyboard false true "/samplechoice1" '|' "/samplechoice2" '|' "/stop")
        tg_do_request sendMessage "chat_id=${chat_id}" "text=Sending reply keyboard" "reply_markup=${keyboard}"
        ;;

      /samplechoice1|/samplechoice2)
        tg_do_request sendMessage "chat_id=${chat_id}" "text=You pressed the '$text' key"
        ;;

      /stop)
        tg_do_request sendMessage "chat_id=${chat_id}" "text=Removing reply keyboard" "reply_markup={\"remove_keyboard\":true}"
        ;;

      /getphoto\ *)

        # THIS ACCESSES LOCAL FILES, FOR TESTING ONLY!!!!

        local photo="${text#/getphoto }"

        if [ -f "$photo" ]; then
          # note the @ before the filename, so the library knows it's a local file
          tg_do_request sendPhoto "chat_id=${chat_id}" "photo=@${photo}" "caption=${photo}"
        else
          tg_do_request sendMessage "chat_id=${chat_id}" "text=Photo '$photo' not found"
        fi
        ;;

      *)
        tg_do_request sendMessage "chat_id=${chat_id}" "text='$text' not implemented"
        ;;
    esac
  fi
}

# process an "inline_query" update
process_inline_query(){

  local update=$1

  local -A inline_query_obj update_obj

  tg_parse_object update_obj "$update"
  tg_parse_object inline_query_obj "${update_obj[inline_query]}"

  # now inline_query_obj has the message

  local from_id=${inline_query_obj[from.id]}
  local query=${inline_query_obj[query]}
  local inline_query_id=${inline_query_obj[id]}

  # what we do here is just send back an inline_query_reply of type "article" with the
  # same query we received, but of course the real thing can and should be more useful

  if [ "$query" = "" ]; then
    return
  fi

  # this has to be an array of results, we use the "InlineQueryResultArticle" here
  declare -A inline_query_reply=()
  inline_query_reply['0.type']="article"
  inline_query_reply['0.id']="$RANDOM"
  inline_query_reply['0.title']="$query"
  inline_query_reply['0.input_message_content.message_text']="$query"

  result_json=$(tg_create_object inline_query_reply)

  tg_do_request answerInlineQuery "inline_query_id=${inline_query_id}" "results=${result_json}"

}


######### BEGIN #################

. bashegram.sh || exit 1

#tg_set_log_level DEBUG  # optional: raise log level

tg_api_init || { tg_log ERROR "Cannot initialize bot API, terminating" && exit 1; }

#tg_set_long_polling_timeout 30   # optional: set long polling timeout (default and maximum: 50 seconds)

tg_set_callback "message" process_message || { tg_log ERROR "Failed to set callback for 'message', terminating" && exit 1; }
tg_set_callback "inline_query" process_inline_query || { tg_log ERROR "Failed to set callback for 'inline_query', terminating" && exit 1; }

# only receive message we can handle
tg_update_filter_disallow "*"
tg_update_filter_allow message inline_query

# optional: filter by user
#tg_sender_disallow "*"
#tg_sender_allow 123456 @johndoe

tg_bot_main_loop

