# Name			WILK
# Author		wilk wilkowy
# Description	Collection of wonderful reusable functions ;-)
# Version		1.4 (2019..2023-05-29)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Important: This script is loaded internally, so if you want to update it call ::wilk::unload first, then .rehash.

namespace eval wilk {

	variable version "1.4"
	variable changed "2023-05-29"
	variable author "wilk"

	namespace export lrandom lsubindices lmatch lshuffle flex minmax_delay strip_codes convert_codes fix_args fix_int get_arg get_str kill_utimer kill_utimers kill_timer kill_timers init_http get_html rest_api http_state recode_html decode_entities trim_text regroup_digits debug_save codepoints json_str sendmsg sendnotc sendact sendinvite settopic setmodes chanjoin getchanlimit getchankey getchanusers chanhasi chanisfull chanhasop chanhasops chanbots myturn isleapyear monthdays handnick

	namespace eval v {
		variable pkg_http
		variable pkg_tls
		variable pkg_htmlparse
		variable http_state
		variable scripts
		variable scriptdir
		variable def_agent "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
		variable def_mime "text/html,application/xhtml+xml,application/atom+xml,application/rss+xml,application/xml,text/xml"
		variable def_lang "pl,en-US;q=0.7,en;q=0.3"
		variable def_timeout 3000
	}

	# Returns random element of a list.
	#
	proc lrandom {list} {
		return [lindex $list [rand [llength $list]]]
	}

	# Returns list of elements on given subindex from a list of lists.
	#
	proc lsubindices {list index} {
		return [lsearch -all -inline -index $index -subindices $list "*"]
	}

	# Returns 1 if text matches one of a patterns. Similar to lsearch, but matches against several patterns.
	#
	proc lmatch {text patterns} {
		foreach pattern $patterns {
			if {[string match -nocase $pattern $text]} {
				return 1
			}
		}
		return 0
	}

	# Returns randomly shuffled elements of a list.
	#
	proc lshuffle {list} {
		set newlist [list]
		set cnt [llength $list]
		while {$cnt > 0} {
			set idx [rand $cnt]
			lappend newlist [lindex $list $idx]
			set list [lreplace $list $idx $idx]
			incr cnt -1
		}
		return $newlist
	}

	# Returns 1 if year is leap
	#
	proc isleapyear {year} {
		return [expr {($year % 4 == 0 && $year % 100 != 0) || $year % 400 == 0}]
	}

	# Returns number of days in month
	#
	proc monthdays {month year} {
		return [lindex [list 31 [expr {[isleapyear $year] ? 29 : 28}] 31 30 31 30 31 31 30 31 30 31] $month-1]
	}

	# Shortcut for sending irc message.
	#
	proc sendmsg {target text} {
		puthelp "PRIVMSG $target :$text"
	}

	# Shortcut for sending irc notice.
	#
	proc sendnotc {target text} {
		puthelp "NOTICE $target :$text"
	}

	# Shortcut for sending irc action.
	#
	proc sendact {target text} {
		puthelp "PRIVMSG $target :\001ACTION $text\001"
	}

	# Shortcut for sending channel invite.
	#
	proc sendinvite {nick chan} {
		putquick "INVITE $nick $chan"
	}

	# Shortcut for setting a topic.
	#
	proc settopic {chan text} {
		putserv "TOPIC $chan :$text"
	}

	# Shortcut for setting channel modes. Use pushmode instead.
	#
	proc setmodes {chan modes} {
		putquick "MODE $chan :$modes"
		#split+pushmode?
	}

	# Join a channel with optional chankey.
	#
	proc chanjoin {chan {key ""}} {
		if {$key ne ""} {
			putserv "JOIN $chan $key"
		} else {
			putserv "JOIN $chan"
		}
	}

	# Returns channel limit or "" if not set.
	#
	proc getchanlimit {chan} {
		# +stn
		# +stnl 10
		# +stnk abc
		# +stnkl abc 10
		set modes [split [getchanmode $chan]]
		if {![string match "*l*" [lindex $modes 0]]} { return "" }
		return [lindex $modes end]
	}

	# Returns channel key or "" if not set.
	#
	proc getchankey {chan} {
		set modes [split [getchanmode $chan]]
		if {![string match "*k*" [lindex $modes 0]]} { return "" }
		return [lindex $modes 1]
	}

	# Returns real (or total) number of channel users. Takes into account a split event.
	#
	proc getchanusers {chan {count_splitted 0}} {
		if {$count_splitted != 0} {
			return [llength [chanlist $chan]]
		}
		set users 0
		foreach nick [chanlist $chan] {
			if {![onchansplit $nick $chan]} {
				incr users
			}
		}
		return $users
	}

	# Returns 1 if channel has +i flag.
	#
	proc chanhasi {chan} {
		return [string match "*i*" [lindex [split [getchanmode $chan]] 0]]
	}

	# Returns 1 if users >= chanlimit. Takes into account a split event.
	#
	proc chanisfull {chan} {
		set limit [getchanlimit $chan]
		if {$limit eq ""} {
			return 0
		}
		set users [getchanusers $chan]
		if {$limit > $users} {
			return 0
		}
		return 1
	}

	# Returns 1 if channel has any user with handle in given handle list, having op and not on split.
	#
	proc chanhasop {chan handles} {
		# hand2nicks is 1.9.x
		foreach hand $handles {
			set nick [hand2nick $hand $chan]
			if {$nick ne "" && ![onchansplit $nick $chan] && [isop $nick $chan]} {
				return 1
			}
		}
		return 0
	}

	# Returns 1 if channel has any user with chanop (and not being on split).
	#
	proc chanhasops {chan} {
		foreach nick [chanlist $chan] {
			if {![onchansplit $nick $chan] && [isop $nick $chan]} {
				return 1
			}
		}
		return 0
	}

	# Returns list of other bots present on given channel. Optionally requires having them @.
	# Requires nick == botnet-nick..
	#
	proc chanbots {chan {needop 0} {needlink 1}} {
		set bots [list]
		foreach hand [userlist "b"] {
			#if {![handonchan $hand $chan]} { continue }
			#foreach nick [hand2nicks]
			set nick [hand2nick $hand $chan]
			if {$nick ne "" &&
				![isbotnick $nick] &&
				[onchan $nick $chan] &&
				(!$needlink || [islinked $nick]) &&
				(!$needop || [isop $nick $chan])
			} then {
				lappend bots $nick
			}
		}
		return $bots
	}

	# If handle is valid return handle, otherwise nick.
	#
	proc handnick {hand nick} {
		if {$hand ne "" && $hand ne " " && $hand ne "*"} {
			return $hand
		} else {
			return $nick
		}
	}

	# Returns 1 if this bot is chosen to act for given channel.
	#
	proc myturn {{id ""} {chan ""} {bots 1} {needop 1} {ignored [list]}} {
		if {$bots < 1} { return 1 }
		set timestamp [string range [unixtime] 0 end-3]
		set this [md5 "$id$timestamp$chan${::botnet-nick}"]
		set hashes [list $this]
		foreach botnick [bots] {
			if {$botnick in $ignored || ($needop && $chan ne "" && (![isop $botnick $chan] || [onchansplit $botnick $chan]))} { continue }
			lappend hashes [md5 "$id$timestamp$chan$botnick"]
		}
		if {$this in [lrange [lsort $hashes] 0 $bots-1]} {
			return 1
		}
		return 0
	}

	# Word inflection.
	# singular = 1; plural24 = x2-x4, except 12-14 (polish case); plural = 0 and other
	#
	proc flex {value singular plural24 plural} {
		if {$value eq ""} { return "" }
		if {abs($value) == 1} { return $singular }
		set digit [string index $value end]
		if {[string index $value end-1] != 1 && $digit >= 2 && $digit <= 4} {
			return $plural24
		}
		return $plural
	}

	# Returns random value between min and max. Value notation is min:max.
	#
	proc minmax_delay {value} {
		set time [split $value ":"]
		if {[llength $time] <= 1} {
			return $value
		}
		lassign $time min max
		if {$min > $max} {
			foreach {min max} [list $max $min] { break }
		}
		return [expr {[rand [expr {$max + 1 - $min}]] + $min}]
	}

	# Similar to stripcodes, but removes more codes.
	#
	proc strip_codes {text} {
		#if {[lindex [split $::version] 1] < 1080000} {
		#	return [stripcodes "bcruag" $text]
		#} else {
		#	return [stripcodes "*" $text]
		#}
		return [regsub -nocase -all {\003(?:\d{1,2}(?:,\d{1,2})?)?|\002|\017|\026|\037|\007|\035|\036|\021|\004(?:[0-9a-f]{6}(?:,[0-9a-f]{6})?)?} $text ""]
	}

	# Telnet does not display control codes properly.
	#
	proc convert_codes {text} {
		return [string map {"\002" "B" "\003" "C" "\017" "P" "\026" "R" "\037" "U" "\035" "I" "\036" "S" "\021" "M"} $text]
	}

	# Cuts text longer than given lenght, appends a suffix.
	#
	proc trim_text {text maxlen marker} {
		if {$maxlen <= 0 || [string length $text] <= $maxlen} {
			return $text
		}
		set trimmed [string range $text 0 $maxlen]
		if {[string length $text] != [string length $trimmed]} {
			append trimmed $marker
		}
		return $trimmed
	}

	# Adds group separator to ints.
	#
	proc regroup_digits {number {per_group 3} {separator " "}} {
		# based on Peter Spjuth code (wiki.tcl.tk/526)
		return [regsub -all "\\d(?=(\\d{$per_group})+($|\[.,]))" $number "\\0$separator"]
	}

	# Fixes ints writen as "1 000", "1,000", "1.000" striping those chars.
	#
	proc fix_int {text} {
		return [regsub -all {[\s,.]+} $text ""]
	}

	# Treats strings given from for example channel command input by trimming leading/following spaces and replacing multiple spaces/tabs to single one.
	#
	proc fix_args {text} {
		return [string trim [regsub -all {\s+} $text " "]]
	}

	# For use with pub/msg handler to retrieve single word from user input.
	#
	proc get_arg {text {idx 0}} {
		return [lindex [split $text] $idx]
	}

	# For use with pub/msg handler to skip first word (format: command text) from user input.
	#
	proc get_str {text {first 1} {last "end"}} {
		return [join [lrange [split $text] $first $last]]
	}

	# Similar to killutimer, but takes as an argument reference to variable storing timer_id and unsets it as well.
	#
	proc kill_utimer {var} {
		if {![info exists $var]} { return 0 }
		set id [set $var]
		# [time_left proc_name timer_id repeats]
		if {[lsearch -exact -index 2 [utimers] $id] != -1} {
			killutimer $id
		}
		unset $var
		return 1
	}

	# Kills all utimers whose timer_id is stored in given array.
	#
	proc kill_utimers {arr} {
		foreach key [array names $arr] {
			kill_utimer ${arr}($key)
		}
	}

	# Similar to killtimer, but takes as an argument reference to variable storing timer_id and unsets it as well.
	#
	proc kill_timer {var} {
		if {![info exists $var]} { return 0 }
		set id [set $var]
		# [time_left proc_name timer_id repeats]
		if {[lsearch -exact -index 2 [timers] $id] != -1} {
			killtimer $id
		}
		unset $var
		return 1
	}

	# Kills all utimers whose timer_id is stored in given array.
	#
	proc kill_timers {arr} {
		foreach key [array names $arr] {
			kill_timer ${arr}($key)
		}
	}

	# For use with multibyte unicode. Does not support U+010000 and higher.
	#
	proc codepoints {text} {
		return [lmap char [split $text ""] { format "%04x" [scan $char "%c"] }]
	}

	# Internal proc used to configure TLS socket.
	# This routine is not exported.
	#
	proc tls_socket {args} {
		if {[package vcompare $v::pkg_tls 1.7.11] >= 0} {
			::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -autoservername 1 {*}$args
		} elseif {[package vcompare $v::pkg_tls 1.6.4] >= 0} {
			set hostname [lindex $args end-1]
			::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -servername $hostname {*}$args
		} else {
			::tls::socket -tls1 1 -ssl3 0 -ssl2 0 {*}$args
		}
	}

	# Initializes http package.
	#
	proc init_http {} {
		if {[info exists v::pkg_http] && $v::pkg_http ne ""} { return 2 }
		if {[catch { set v::pkg_http [package require http] }]} {
			set v::pkg_http ""
			putlog "WILK: no http package = no web access (HTTP)"
		}
		if {![catch { set v::pkg_tls [package require tls] }]} {
			if {[package vcompare $v::pkg_tls 1.6.4] < 0} {
				putlog "WILK: tls package version <1.6.4 = no SNI support (some HTTPS links will not work)"
			} elseif {[package vcompare $v::pkg_tls 1.7.11] < 0} {
				putlog "WILK: tls package version <1.7.11 = SNI support is present, but consider upgrading package"
			}
			::http::register https 443 [namespace current]::tls_socket
		} else {
			set v::pkg_tls ""
			putlog "WILK: no tls package = no SSL/TLS support (HTTPS links won't work)"
		}
		if {[catch { set v::pkg_htmlparse [package require htmlparse] }]} {
			set v::pkg_htmlparse ""
			putlog "WILK: no htmlparse package = no escape sequences substitution"
		}
		return [expr {$v::pkg_http ne "" ? 1 : 0}]
	}

	# Debug proc to report currently used packages and its version.
	# This routine is not exported.
	#
	proc pkg_versions {} {
		if {[info exists v::pkg_http]} {
			putlog "WILK: http = $v::pkg_http"
		}
		if {[info exists v::pkg_tls]} {
			putlog "WILK: tls = $v::pkg_tls"
		}
		if {[info exists v::pkg_htmlparse]} {
			putlog "WILK: htmlparse = $v::pkg_htmlparse"
		}
	}

	# Request an html file contents from web.
	#
	proc get_html {url args} {
		array set opts [concat {-agent $v::def_agent -mime $v::def_mime -lang $v::def_lang -timeout $v::def_timeout -depth 5 -referrer "" -cookies [list]} $args]

		if {[string length $url] == 0} { return "" }
		unset -nocomplain v::http_state

		if {$opts(-depth) < 0} {
			set v::http_state(ncode) -2
			set v::http_state(status) "redir"
			return ""
		}
		if {[string match -nocase "www.*" $url]} {
			set url "http://$url"
		}
		::http::config -useragent $opts(-agent)
		# Accept header if honored might conserve bandwidth by not downloading other content types (error 406)
		# Accept-Encoding is required due to bug in some versions of http package (wrong order)
		set headers [list "Accept" $opts(-mime) "Accept-Encoding" "gzip,deflate" "Accept-Language" $opts(-lang)]
		if {$opts(-referrer) ne ""} {
			lappend headers "Referer" $opts(-referrer)
		}
		if {[llength $opts(-cookies)] > 0} {
			lappend headers "Cookie" [string trim [join $opts(-cookies) ";"] ";"]
		}
		catch { set http [::http::geturl $url -timeout $opts(-timeout) -headers $headers] } httperror
		if {![info exists http]} {
			putlog "WILK: connection failed to $url ($httperror)"
			# state array is not created and there is nothing to copy - we simulate parts of it
			set v::http_state(ncode) -1
			set v::http_state(status) "failed"
			set v::http_state(error) $httperror
			return ""
		}
		#upvar #0 $http state
		array set v::http_state [array get $http]
		set status [::http::status $http]
		set error [::http::error $http]
		set ncode [::http::ncode $http]
		# for whatever reason raw ncode is not part of state array so we add it
		set v::http_state(ncode) $ncode
		set html ""
		if {$status eq "ok"} {
			if {$ncode in [list 301 302 303 307]} {
				set redirect ""
				set cookies [list]
				foreach {name value} $v::http_state(meta) {
					if {[string equal -nocase "Location" $name]} {
						set redirect $value
					} elseif {[string equal -nocase "Set-Cookie" $name]} {
						lappend cookies [lindex [split $value ";"] 0]
					}
				}
				#if {[llength $cookies] == 0} {
				#	set cookies $opts(-cookies)
				#}
				if {$redirect ne ""} {
					::http::cleanup $http
					set hostname ""
					if {[regexp -nocase {^https?://[^/&?]+?} $url hostname] && ![regexp -nocase {^https?://} $redirect]} {
						# some broken sites provide relative uri for redirections
						#array set parts [::uri::split $url]
						#set redirect "$parts(scheme)://$parts(host)$redirect"
						set redirect "$hostname$redirect"
					}
					#tailcall?
					return [get_html $redirect -agent $opts(-agent) -mime $opts(-mime) -lang $opts(-lang) -timeout $opts(-timeout) -depth [expr {$opts(-depth) - 1}] -referrer $hostname -cookies $cookies]
				}
			}
			if {[lmatch $v::http_state(type) [list "text/html*" "application/xhtml+xml*" "application/atom+xml*" "application/rss+xml*" "application/xml*" "text/xml*"]]} {
				set html [::http::data $http]
			} else {
				putlog "WILK: unsupported content-type for $url ($v::http_state(type))"
			}
		} else {
			set logmsg "WILK: connection error for $url ($status"
			if {$error ne ""} {
				append logmsg " / $error"
			}
			putlog "$logmsg)"
			set v::http_state(ncode) -3
		}
		::http::cleanup $http
		return $html
	}

	# Returns a copy of internal http_state array. 
	#
	proc http_state {elem} {
		if {[info exists v::http_state($elem)]} {
			return $v::http_state($elem)
		}
		return ""
	}

	# Extends and fixes default http package character encoding.
	#
	proc recode_html {text} {
		set body_charset ""
		if {[string match -nocase "application*" $v::http_state(type)]} {
			# http package does internal encoding for text* only, otherwise it treats data as binary
			regexp -nocase {<\?xml[^>]+?encoding="([^"]+?)"} $v::http_state(body) match body_charset ;#"
		} else {
			# http package does content encoding according to header charset, but some servers are broken (default charset is different than content), so we reencode using meta tag charset if both differ
			regexp -nocase {<meta[^>]+?charset="?([^"]+?)"} $v::http_state(body) match body_charset ;#"
		}
		if {$body_charset ne ""} {
			set header_encoding [::http::CharsetToEncoding $v::http_state(charset)]
			set body_encoding [::http::CharsetToEncoding $body_charset]
			if {![string equal -nocase $header_encoding $body_encoding] && $body_encoding ne "binary"} {
				return [encoding convertfrom $body_encoding $text]
			}
		}
		return $text
	}

	# Decodes HTML entities.
	#
	proc decode_entities {text} {
		if {[info exists v::pkg_htmlparse] && $v::pkg_htmlparse ne ""} {
			return [::htmlparse::mapEscapes $text]
		}
		return $text
	}

	# JSON-izes string for use with REST requests.
	#
	proc json_str {text} {
		return [string map {"\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"} [encoding convertto [encoding system] $text]]
	}

	# Makes REST request with given JSON payload.
	#
	proc rest_api {url json args} {
		array set opts [concat {-agent $v::def_agent -timeout $v::def_timeout} $args]
		::http::config -useragent $opts(-agent)
		catch { set http [::http::geturl $url -timeout $opts(-timeout) -type "application/json" -query $json] } httperror
		if {![info exists http]} {
			putlog "WILK: connection failed to $url ($httperror)"
			return
		}
		set status [::http::status $http]
		set error [::http::error $http]
		set ncode [::http::ncode $http]
		if {$status ne "ok"} {
			set logmsg "WILK: connection error for $url ($status"
			if {$error ne ""} {
				append logmsg " / $error"
			}
			putlog "$logmsg)"
		}
		::http::cleanup $http
		return $ncode
	}

	# Dump http connection data to debug file.
	# Mode: 0 - disabled, 1 - enabled if ok == 1, 2 - enabled
	#
	proc debug_save {mode ok text prefix} {
		if {($ok && $mode != 2) ||
			(!$ok && !$mode) ||
			![info exists v::http_state(type)] ||
			![lmatch $v::http_state(type) [list "text/html*" "application/xhtml+xml*" "application/atom+xml*" "application/rss+xml*" "application/xml*" "text/xml*" "text/plain"]]
		} then { return }
		set file [open "$v::scriptdir/${prefix}_[format "%06d" [rand 1000000]].dat" w 0600]
		puts $file $text
		if {[info exists v::http_state(body)]} {
			puts $file [string repeat "-" 80]
			puts $file $v::http_state(body)
		}
		close $file
	}

# -=-=-=-=-=-

	# Call this internal proc to register a script following init/unload/uninstall scheme. Well, only unload is used.
	# This routine is not exported.
	#
	proc register {ns} {
		dict set v::scripts $ns 1
	}

	# Call this internal proc to unload all registered scripts from Eggdrop's memory.
	# This routine is not exported.
	#
	proc unload_all {{keepns 0}} {
		foreach ns [dict keys $v::scripts] {
			#if {[info exists ::${ns}::v::version]} {
			${ns}::unload $keepns
			#}
		}
	}

# -=-=-=-=-=-

	# Standard three procs in my every script. This one is to initialize script and display "loaded" message.
	proc init {} {
		variable version; variable author

		set v::scripts [dict create]
		# [info script] is valid only on load
		set v::scriptdir [file dirname [info script]]

		putlog "WILK v$version by $author"
	}

	# Normally this one is to unbind event handlers, terminate timers and if not objected by setting keepns to 1 remove its namespace from Eggdrop. Here we default to 1 however, because removing this namespace will break every other loaded script.
	proc unload {{keepns 1}} {
		variable version
		# Let's use ::wilk::version as a flag so we can call ::wilk::unload to reload this file with next .rehash if wilk.tcl is not added to eggdrop.conf directly while not breaking any depending scripts by deleting this namespace (moved to uninstall).
		unset version
		unset -nocomplain v::pkg_http

		if {!$keepns} {
			namespace delete [namespace current]
		}
	}

	# Normally this one is to unload script and remove any presence of the script changes to Eggdrop's config (like channel flags), external files with databases etc., but here we only unload everything.
	proc uninstall {} {
		unload_all
		unload 0
	}

	init
}
