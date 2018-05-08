#!/bin/bash

declare -A tg_update_types=( [message]=1
                             [edited_message]=1
                             [channel_post]=1
                             [edited_channel_post]=1
                             [inline_query]=1
                             [chosen_inline_result]=1
                             [callback_query]=1
                             [shipping_query]=1
                             [pre_checkout_query]=1 )

declare -A tg_methods=( [getme]=1
                        [getupdates]=1
                        [sendmessage]=1
                        [deletemessage]=1
                        [sendlocation]=1
                        [sendvenue]=1
                        [sendcontact]=1
                        [sendchataction]=1
                        [forwardmessage]=1
                        [answerinlinequery]=1
                        [sendphoto]=1
                        [sendaudio]=1
                        [senddocument]=1
                        [sendvideo]=1
)

declare -A tg_chat_actions=( [typing]=1
                             [upload_photo]=1
                             [record_video]=1
                             [record_audio]=1
                             [upload_document]=1
                             [find_location]=1
                             [record_video_note]=1
                             [upload_video_note]=1
)

declare -A tg_inline_query_result_types=(
                                    [article]=1
                                    [photo]=1
                                    [gif]=1
                                    [mpeg4_gif]=1
                                    [video]=1
                                    [audio]=1
                                    [voice]=1
                                    [document]=1
                                    [location]=1
                                    [venue]=1
                                    [contact]=1
                                    [game]=1
                                    [cached_photo]=1
                                    [cached_gif]=1
                                    [cached_mpeg4_gif]=1
                                    [cached_sticker]=1
                                    [cached_document]=1
                                    [cached_video]=1
                                    [cached_voice]=1
                                    [cached_audio]=1
)

declare -A tg_parse_modes=( [Markdown]=1
                            [HTML]=1
)

declare -A tg_lib=()

declare -A tg_user_update_filter=()
declare -a tg_update_queue=()
declare -A tg_user_callbacks=()

declare -A tg_user_senders=()

declare -A tg_log_levels=( [DEBUG]=0 [INFO]=1 [NOTICE]=2 [WARNING]=3 [ERROR]=4 )

tg_set_current_offset(){
  local offset=$1
  tg_lib['current_offset']=$offset
}

tg_is_valid_parse_mode(){
  local parse_mode=$1
  tg_array_has_key tg_parse_modes "$parse_mode"
}

tg_is_valid_chat_action(){
  local chat_action=$1
  tg_array_has_key tg_chat_actions "$chat_action"
}

tg_is_valid_method(){
  local method=$1
  tg_array_has_key tg_methods "$method"
}

tg_is_valid_inline_query_result_type(){
  local type=$1
  tg_array_has_key tg_inline_query_result_types "$type"
}

# pure bash URL enconding, thanks to
# https://gist.github.com/cdown/1163649
tg_percent_encode() {

  local old_lc_collate=$LC_COLLATE
  LC_COLLATE=C

  local length=${#1}
  local offset char

  local result=

  for (( offset = 0; offset < length; offset++ )); do
    char=${1:$offset:1}

    case "$char" in
      [a-zA-Z0-9.~_-])
        result="${result}${char}"
        ;;
      *)
        result="${result}$(printf '%%%X' "'$char")"
         ;;
    esac
  done

  LC_COLLATE=$old_lc_collate

  echo "$result"
}

# parse a JSON object into a user-specified array
tg_parse_object(){
  local json=$2 key value
  local -n obj_array=$1

  obj_array=()
  while IFS="=" read -r key value; do
    obj_array[$key]="${value//$'\x1'/$'\n'}"
  done < <(${tg_lib['jq']} -r 'paths as $p | [ $p, (getpath($p) | if type == "string" then gsub("\n"; "\u0001") else . end ) ] | "\(.[0] | map(tostring) | join("."))=\(.[1])"' <<< "$json")
}

# creates a JSON string from a user-specified associative array (keys are paths)
tg_create_object(){

  local -n obj_array=$1

  local code json=

  json=$(
    ${tg_lib['jq']} -c -n -R '
      reduce inputs as $e (
        null;
        setpath($e | split("=") | .[0] | split(".") | map(. as $i | try tonumber catch $i);
        $e | split("=") | .[1] | gsub("\u0001"; "\n") as $v | try fromjson catch $v))
    ' < <(for key in "${!obj_array[@]}"; do echo "${key}=${obj_array[$key]//$'\n'/$'\x1'}"; done)
  )

  code=$?

  echo "$json"
  return $code   # check this!

}

tg_array_has_key(){
  local key=$2
  local -n _object_arr=$1

  [[ "${_object_arr[$key]+foobar}" ]]
}

tg_get_curtime(){
  printf '%(%Y-%m-%d %H:%M:%S)T\n' -1
}

tg_lib['curtime']=$(tg_get_curtime)
tg_lib['curtime']=${tg_lib['curtime']/ /_}

tg_lib['log_file']="/tmp/bashegram_${tg_lib['curtime']}.log"

tg_log(){

  local level=$1 msg=$2

  local curtime=$(tg_get_curtime)
 
  if [ ${tg_lib['logging_enabled']} != "0" ] && [ ${tg_log_levels[$level]} -ge ${tg_lib['current_log_level']} ]; then
    if [ "${tg_lib['log_destination']}" = "stdout" ]; then
      echo "$curtime $level: $msg"
    else
      echo "$curtime $level: $msg" >> "${tg_lib['log_file']}"
    fi
  fi
}

tg_set_log_level(){
  tg_lib['current_log_level']=${tg_log_levels[$1]}

  if [ "${tg_lib['current_log_level']}" = "" ]; then
    tg_lib['current_log_level']=${tg_log_levels[INFO]}
  fi
}

tg_set_long_polling_timeout(){
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    tg_lib['long_polling_timeout']=$1

    if [ ${tg_lib['long_polling_timeout']} -gt 50 ]; then
      # after 50 seconds telegram answers anyway, so...
      tg_lib['long_polling_timeout']=50
    fi
  fi
}

tg_set_periodic_callback(){
  local periodic_callback_func=$1
  if [ "${periodic_callback_func}" != "" ] && declare -f "$periodic_callback_func" >/dev/null; then
    tg_periodic_callback_func=$periodic_callback_func
  fi
}

tg_set_logging_enabled(){
  tg_lib['logging_enabled']=$1    # 0 disabled, anything else enabled
}

tg_set_log_destination(){
  if [ "$1" = "" ]; then
    if [ -t 1 ]; then
      # log to stdout
      tg_lib['log_destination']="stdout"
    else
      # log to file
      tg_lib['log_destination']="file"
    fi
  else
    tg_lib['log_destination']="$1"
    [[ ! "${tg_lib['log_destination']}" =~ ^(stdout|file)$ ]] && tg_lib['log_destination']=stdout
  fi
}

#### DEFAULT VALUES
tg_set_log_level INFO
tg_set_logging_enabled "1"
tg_set_log_destination
tg_set_long_polling_timeout 50

tg_get_credentials(){

  tg_log INFO "Getting bot credentials..."

  local tg_userdef_cred_function=tg_get_userdef_credentials

  if ! declare -F $tg_userdef_cred_function >/dev/null; then
    tg_log ERROR "Function '$tg_userdef_cred_function()' does not exist, must define it and make sure it sets variable 'tg_lib[bot_token]'"
    return 1
  fi

  $tg_userdef_cred_function   # user MUST implement this

  [ "${tg_lib['bot_token']}" != "" ] || \
    { tg_log ERROR "Cannot get bot credentials; make sure '$tg_userdef_cred_function()' sets variables 'tg_lib[bot_token]'" && return 1; }
}

tg_check_required_binaries(){

  tg_log INFO "Checking required binaries..."
    
  local retcode=0

  tg_lib['curl']=$(command -v curl)
  tg_lib['jq']=$(command -v jq)
  tg_lib['awk']=$(command -v awk)

  ( [ "${tg_lib['curl']}" != "" ] && \
    [ "${tg_lib['awk']}" != "" ] && \
    [ "${tg_lib['jq']}" != "" ] ) || \
  { tg_log ERROR "Cannot find needed binaries, make sure you have curl, awk, jq in your PATH" && return 1; }
}

tg_check_api_initialized(){
  if [ "${tg_lib['api_initialized']}" != "1" ]; then
    tg_log ERROR "telegram API not initialized, call tg_api_init first"
    return 1
  fi
}

tg_reset_user_update_filter(){
  tg_user_update_filter=()
}

tg_compute_update_filter_parstring(){

  local all_allowed=1
  tg_lib['update_filter_parstring']="allowed_updates=[]"

  local update_type
  local sep list_str


  for update_type in "${!tg_update_types[@]}"; do
    if [ "${tg_user_update_filter[$update_type]}" = "0" ] || \
       ( [ "${tg_user_update_filter["*"]}" = "0" ] && [ "${tg_user_update_filter[$update_type]}" != "1" ] ); then
      all_allowed=0
    else
      list_str="${list_str}${sep}\"${update_type}\""
      sep=","
    fi 

  done

  if [ $all_allowed -ne 1 ]; then
    tg_lib['update_filter_parstring']="allowed_updates=[${list_str}]"
  fi

}

tg_update_filter_modify(){

  local allow=$1
  shift

  local allow_desc

  allow_desc="allow"
  if [ "$allow" = "0" ]; then
    allow_desc="disallow"
  fi

  while [ "$1" != "" ]; do
    if [ "${tg_update_types[$1]}" != "" ] || [ "$1" = "*" ]; then
      tg_log DEBUG "Adding $1 to update filter ($allow_desc)"
      tg_user_update_filter[$1]=$allow
    else
      tg_log WARNING "Not adding $1 to update filter ($allow_desc), invalid type"
    fi
    shift
  done

  # recompute filter parstring
  tg_compute_update_filter_parstring

}

tg_update_filter_allow(){
  tg_update_filter_modify 1 "$@"
}

tg_update_filter_disallow(){
  tg_update_filter_modify 0 "$@"
}

tg_sender_allow(){
  tg_sender_modify 1 "$@"
}

tg_sender_disallow(){
  tg_sender_modify 0 "$@"
}

tg_sender_modify(){

  local allow=$1
  shift

  local allow_desc

  allow_desc="allow"
  if [ "$allow" = "0" ]; then
    allow_desc="disallow"
  fi

  while [ "$1" != "" ]; do
    tg_user_senders[$1]=$allow
    tg_log DEBUG "Adding $1 to sender filter ($allow_desc)"
    shift
  done
}


tg_api_init(){
  tg_log NOTICE "Telegram API initialization starting..."
  tg_log NOTICE "Checking for bash >= 4.3..."
  ( [ ${BASH_VERSINFO[0]} -ge 4 ] && [ ${BASH_VERSINFO[1]} -ge 3 ] ) || return 1
  tg_check_required_binaries || return 1
  tg_get_credentials || return 1

  tg_lib['bot_token_encoded']=$(tg_percent_encode "${tg_lib['bot_token']}")

  tg_lib['api_initialized']=1

  tg_log NOTICE "Getting self-information"
  tg_get_self_info || return 1
  tg_compute_update_filter_parstring

  # allow everyone by default
  tg_user_senders["*"]=1
  tg_set_current_offset 0   # set to 0 to get everything
  tg_periodic_callback_func=
  tg_log NOTICE "API initialized"
}

tg_get_self_info(){

  tg_do_request "getMe" || return 1

  if [ "${tg_lib['last_http_code']}" != "200" ]; then
    tg_log ERROR "Cannot retrieve information about the bot (code ${tg_lib['last_http_code']})"
    return 1
  fi

  local -A self_info_obj
  tg_parse_object self_info_obj "${tg_lib['last_http_body']}"
 
  #tg_dump_object self_info_obj
 
  tg_lib['bot_username']=${self_info_obj['result.username']}
  tg_lib['bot_id']=${self_info_obj['result.id']}
  tg_lib['bot_name']="${self_info_obj['result.first_name']}"
  if [ "${self_info_obj['result.last_name']}" != "" ]; then
    tg_lib['bot_name']="${tg_lib['bot_name']} ${self_info_obj['result.last_name']}"
  fi

}

tg_get_update_type(){

  local update_type
  local -n object_arr=$1

  for update_type in "${!tg_update_types[@]}"; do
    if tg_array_has_key object_arr "${update_type}"; then
      echo "$update_type"
      return
    fi
  done 
  
}

tg_check_sender_allowed(){

  local update_type=$1
  local from_id=$2 from_username=$3

  # check for explicit permission/denial
  if [[ "${tg_user_senders[$from_id]}" =~ ^[01]$ ]]; then
    return $(( ! ${tg_user_senders[$from_id]} ))
  fi

  if [ "$from_username" != "" ]; then
    if [[ "${tg_user_senders[@$from_username]}" =~ ^[01]$ ]]; then
      return $(( ! ${tg_user_senders[@$from_username]} ))
    fi
  fi

  # check default policy
  if [ "${tg_user_senders["*"]}" = "0" ]; then
    return 1
  fi

  # default is allowed
  return 0

}

tg_get_maybe_updates(){

  local timeout=$1

  local last_id=
  local result ok description update
  local offset

  offset="offset=${tg_lib['current_offset']}"

  tg_do_request "getUpdates" "timeout=${timeout}" "${tg_lib['update_filter_parstring']}" "${offset}" || continue

  if [ $? -ne 0 ]; then
    return 1
  fi

  if [ "${tg_lib['last_http_code']}" != "200" ]; then
    tg_log ERROR "Bad HTTP code (${tg_lib['last_http_code']}), skipping"
    return 1
  fi

  local -A response_obj
  tg_parse_object response_obj "${tg_lib['last_http_body']}"

  if [ "${response_obj['ok']}" != "true" ]; then
    tg_log ERROR "Error: ${response_obj['description']}"
    return 1
  fi

  # if we get here, query was successful, put result(s) in the queue

  local update_count=0

  while tg_array_has_key response_obj "result.${update_count}"; do

    last_id=${response_obj[result.${update_count}.update_id]}
    tg_set_current_offset $(( last_id + 1 ))
    tg_update_queue+=( "${response_obj[result.${update_count}]}" )

    ((update_count++))
  done

  return 0

}

tg_dequeue_update(){

  local i

  for ((i=0; i< ${#tg_update_queue[@]} - 1; i++)); do
    tg_update_queue[$i]=${tg_update_queue[$i+1]}
  done

  if [ ${#tg_update_queue[@]} -gt 0 ]; then
    unset tg_update_queue[${#a[@]}-1]
  fi
}

tg_queue_has_updates(){
  [ ${#tg_update_queue[@]} -gt 0 ]
}

tg_get_first_update(){
  if tg_queue_has_updates; then
    echo "${tg_update_queue[0]}"
  fi
}

tg_dispatch_updates(){

  local do_filter=$1

  while tg_queue_has_updates; do

    local update=$(tg_get_first_update)

    local -A update_obj

    tg_parse_object update_obj "$update"

    local update_type=$(tg_get_update_type update_obj)

    if [ "$update_type" = "" ]; then

      tg_log ERROR "Cannot determine update type for update $update, skipping"

    else

      local dispatch=1

      if [ "$do_filter" = "1" ]; then
        if [[ "$update_type" =~ ^(edited_)?message$ ]]; then
          # check for allowed users
          local sender_id=${update_obj[${update_type}.from.id]}
          local sender_username=${update_obj[${update_type}.from.username]}
          if ! tg_check_sender_allowed "$update_type" "${sender_id}" "${sender_username}"; then
            dispatch=0
          fi
        fi
      fi

      if [ $dispatch = "1" ]; then
        tg_dispatch_update "$update" "${update_type}"
      else
        tg_log NOTICE "sender ${sender_id} (${sender_username}) disallowed, discarding message"
      fi

    fi

    tg_dequeue_update
  done

}


tg_dispatch_update(){

  local update=$1 update_type=$2

  tg_log DEBUG "Update is of type $update_type"

  local callback_func=${tg_user_callbacks[$update_type]}

  if [ "${callback_func}" != "" ] && declare -f "$callback_func" >/dev/null; then
    tg_log DEBUG "calling user callback for '$update_type': '$callback_func'"
    "$callback_func" "${update}"
  else
    tg_log WARNING "no callback defined for update type '$update_type', discarding message"
  fi
}

tg_get_queue_length(){
  echo "${#tg_update_queue[@]}"
}

tg_bot_main_loop(){

  tg_last_periodic_callback_invocation=$(printf '%(%s)T\n' -1)

  local before_length after_length before after

  local timeout=${tg_lib['long_polling_timeout']}

  while true; do

    before=$(printf '%(%s)T\n' -1)
    before_length=$(tg_get_queue_length)

    if tg_get_maybe_updates ${timeout}; then

      after=$(printf '%(%s)T\n' -1)
      after_length=$(tg_get_queue_length)

      if [ $after_length -eq $before_length ]; then
        # no new messages, timeout expired
        timeout=${tg_lib['long_polling_timeout']}
      else
        timeout=$(( ${timeout} - ( $after - $before ) ))
      fi
      if [ $timeout -le 0 ]; then
        timeout=${tg_lib['long_polling_timeout']}
      fi

      tg_dispatch_updates 1
    fi

    if [ "$tg_periodic_callback_func" != "" ]; then

      local now=$(printf '%(%s)T\n' -1)

      if [ $(( now - tg_last_periodic_callback_invocation )) -ge ${tg_lib['long_polling_timeout']} ]; then
        $tg_periodic_callback_func
        tg_last_periodic_callback_invocation=$now
      fi
    fi

    sleep 0.1
  done
}

tg_set_callback(){

  local update_type=$1
  local callback_func=$2

  if [ "${tg_update_types[$update_type]}" = "1" ] && declare -F "$callback_func" >/dev/null; then
    tg_log DEBUG "Adding user callback for $update_type: $callback_func"
    tg_user_callbacks[$update_type]=$callback_func
    return 0
  else
    tg_log WARNING "Cannot add user callback for $update_type: $callback_func"
    return 1
  fi
}

# debug
tg_dump_object(){

  local -n arr=$1

  local key

  for key in "${!arr[@]}"; do
    echo "$1['$key']=\"${arr[$key]}\""
  done


}

# use POST and multipart encoding for everything
tg_do_curl(){

  local result
  local method=$1

  shift

  local request_url="https://api.telegram.org/bot${tg_lib['bot_token_encoded']}/${method}"

  local -a fixed_args=( "${tg_lib['curl']}" "-X" "POST" "-g" "--compressed" "-s" \
                        "-H" "Expect:" "-D-" "$request_url" )

  local -a request_args=()
  local arg

  for arg in "$@"; do
    local switch="--form-string"
    # if it's a real file, we use -F
    if [[ "${method,,?},${arg}" =~ ^(sendphoto,photo=@|sendaudio,audio=@|senddocument,document=@|sendvideo,video=@) ]]; then
      switch="-F"
    fi

    request_args+=( "$switch" "$arg" )
  done

  tg_log DEBUG "Running request '$method' with arguments:$(printf " '%s'" "${fixed_args[@]}" "${request_args[@]}")"

  result=$(
    "${fixed_args[@]}" "${request_args[@]}"
  )

  local code=$?

  if [ $code -ne 0 ]; then
    return $code
  fi

  tg_lib['last_http_headers']=$(${tg_lib['awk']} '/^\r$/{ exit }1' <<< "$result")
  tg_lib['last_http_body']=$(${tg_lib['awk']} 'ok; /^\r$/ { ok = 1 }' <<< "$result")
  tg_lib['last_http_code']=$(${tg_lib['awk']} '/^HTTP/ { print $2; exit }' <<< "$result")

  tg_log DEBUG "Request got HTTP code: ${tg_lib['last_http_code']}"
  #tg_log DEBUG "Request got HTTP headers: ${tg_lib['last_http_headers']}"
  return 0
}

tg_check_mandatory_args(){

  local -n arg_array=$1
  shift

  local -A passed_args=()

  local arg

  for arg in "$@"; do    
    passed_args[${arg%%=*}]=1
  done

  for arg in "${arg_array[@]}"; do
    if ! tg_array_has_key passed_args "$arg"; then
      return 1
    fi
  done

  return 0
}

tg_do_request(){

  if ! tg_check_api_initialized; then
    return
  fi

  local method=$1

  if ! tg_is_valid_method "${method,,?}"; then
    tg_log ERROR "Invalid or not implemented method '$method' requested"
    return 1
  fi

  shift

  local valid_values=1 err_msg=
  local -a mandatory_args=()

  case "${method,,?}" in

    getme)

      ;;

    getupdates)

      ;;

    sendmessage)
      mandatory_args=( chat_id text )
      ;;

    deletemessage)
      mandatory_args=( chat_id message_id )
      ;;

    sendlocation)
      mandatory_args=( chat_id latitude longitude )
      ;;

    sendvenue)
      mandatory_args=( chat_id latitude longitude title address )
      ;;

    sendcontact)
      mandatory_args=( chat_id phone_number first_name )
      ;;

    sendchataction)
      mandatory_args=( chat_id action )
      local action=$(tg_get_arg_value action "$@")
      if ! tg_is_valid_chat_action "$action"; then
        err_msg="Invalid chat action $action"
        valid_values=0
      fi
      ;;

    forwardmessage)
      mandatory_args=( chat_id from_chat_id message_id )
      ;;

    answerinlinequery)
      mandatory_args=( inline_query_id results )
      ;;

    sendphoto)
      mandatory_args=( chat_id photo )
      local photo=$(tg_get_arg_value photo "$@")
      if ! tg_check_valid_file "$photo"; then
        err_msg="Invalid path for photo: '$photo'"
        valid_values=0
      fi
      ;;

    sendaudio)
      mandatory_args=( chat_id audio )
      local audio=$(tg_get_arg_value audio "$@")
      if ! tg_check_valid_file "$audio"; then
        err_msg="Invalid path for audio: '$audio'"
        valid_values=0
      fi
      ;;

    senddocument)
      mandatory_args=( chat_id document )
      local document=$(tg_get_arg_value document "$@")
      if ! tg_check_valid_file "$document"; then
        err_msg="Invalid path for document: '$document'"
        valid_values=0
      fi
      ;;
    
    sendvideo)
      mandatory_args=( chat_id video )
      local video=$(tg_get_arg_value video "$@")
      if ! tg_check_valid_file "$video"; then
        err_msg="Invalid path for video: '$video'"
        valid_values=0
      fi
      ;;

    *)
      ;;
  esac

  if ! tg_check_mandatory_args mandatory_args "$@"; then
    tg_log ERROR "Missing mandatory arguments to $method (one of ${mandatory_args[*]})"
    return 1
  fi

  if [ $valid_values -eq 0 ]; then
    tg_log ERROR "$err_msg in $method"
    return 1
  fi

  local code
  tg_do_curl "$method" "$@"
  code=$?

  if [ $code -ne 0 ]; then
    tg_log ERROR "Error making curl request ($code)"
    return $code
  fi

  tg_log DEBUG "Last http body: ${tg_lib['last_http_body']}"

  return 0
}

tg_get_arg_value(){
  local arg=$1
  shift

  local key value

  while [ $# -gt 0 ]; do
  
    key=${1%%=*}
    value=${1#*=}

    if [ "$key" = "$arg" ]; then
      echo "$value"
      return
    fi
    shift
  done
}

tg_check_valid_file(){

  local file=$1

  if [[ "$file" =~ ^@ ]]; then
    # local file
    if [ ! -f "${file#@}" ]; then
      return 1
    fi
  elif [ "$file" = "" ]; then
    return 1
  fi

  return 0 
}

tg_create_reply_keyboard(){

  local reply_keyboard=

  local one_time_keyboard=$1 resize_keyboard=$2

  shift 2

  local arg

  local -A keyboard=()

  keyboard['one_time_keyboard']=$one_time_keyboard
  keyboard['resize_keyboard']=$resize_keyboard

  local row=0 column=0

  for arg in "$@"; do

    if [ "$arg" = "|" ]; then
      ((row++))
      column=0
      continue
    fi

    # MUST be string or object 
    keyboard["keyboard.${row}.${column}"]="\"${arg}\""
    #keyboard["keyboard.${row}.${column}"]="${arg}"
    ((column++))
  done

  tg_create_object keyboard
}
