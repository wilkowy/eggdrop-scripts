# Name			Memo
# Author		wilk wilkowy
# Description	Stores various informations like memo or dictionary in key-value fashion, allows tokens
# Version		1.3 (2019..2021-03-28)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: memo

# Partyline commands: .memo
# .memo search <pattern>		- search for all memos (keys and data) matching given pattern
# .memo deref <key>				- search for all memos referring (alias/token) given key
# .memo query <key>				- display memo (without substitutions)
# .memo add <key> <text>		- add/modify memo
# .memo delete <key>			- delete memo
# .memo rename <key> <newkey>	- rename memo
# .memo list					- list all memos
# .memo validate				- checks for missing alias/token references
# .memo stats					- display number of entries in database and memory taken
# .memo reload					- reload database
# .memo save					- not really needed, just for the sake

# Channel commands:
# !memo <key>				- display memo
# !memo <key> <text>		- add/modify memo
# !memo+ <key> <text>		- append text to memo
# !memo- <key>				- delete memo
# !memo= <key> <newkey>		- rename memo
# !memo0 <key>				- display memo (without substitutions)
# !memo? <pattern>			- display all memos (keys) matching given pattern
# !memo?? <pattern>			- display all memos (data) matching given pattern

# Private commands are the same as channel ones, but without prefix.

# Aliases are like: {otherkey}
# Substitutions are like: text {key} text
# Available placeholders: #NICK#, #IDENT#, #HOST#, #HAND#, #CHAN#, #KEY#, #QUERY#

# ToDo:
# - per channel databases?
# - #RNDKEY#
# - mark words with bold/underline if are a key

namespace eval memo::c {

# Users having such flags can trigger channel query commands. (use - or -|- to allow all)
variable allowed_users "-|-"

# Users having such flags can trigger private query commands. (use - or -|- to allow all)
variable allowed_prvusers "n|n"

# Users having such flags can trigger moderation commands. (use - or -|- to allow all)
variable editor_users "n|n"

# Users having such flags cannot trigger channel/private commands. (use "" to disable)
variable ignored_users "I|I"

# Channel command prefix.
variable cmd_prefix "!"

# Channel command names.
variable cmd_name_query "memo"
variable cmd_name_append "memo+"
variable cmd_name_delete "memo-"
variable cmd_name_rename "memo="
variable cmd_name_raw "memo0"
variable cmd_name_search "memo?"
variable cmd_name_vsearch "memo??"

# Protect against !memo command floods, in seconds. (0 - off)
variable antiflood_delay 2

# File that stores all memos.
variable memo_file "scripts/wilk/memo.db"

# File that stores dump of database when using .memo list ("" - no dump).
variable memo_dump "scripts/wilk/memo.txt"

# Maximum number of redirections for aliases and maximum number of substitution rounds for in-place tokens.
variable max_redirections 10
variable max_substitutions 30

# Max matches for channel searching commands.
variable max_matches 10

}

# #################################################################### #

namespace eval memo {

	variable version "1.3"
	variable changed "2021-03-28"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
		variable database
	}

	proc on_dcc_cmd {hand idx text} {
		if {[regexp -nocase {^search (.+)$} $text match arg]} {
			search_db $idx $arg
		} elseif {$text eq "list"} {
			list_memos $idx
		} elseif {$text eq "validate"} {
			validate_db $idx
		} elseif {$text eq "stats"} {
			show_stats $idx
		} elseif {$text eq "save"} {
			save_database
		} elseif {$text eq "reload"} {
			load_database
		} elseif {[regexp -nocase {^query (.+)$} $text match arg]} {
			query_db $idx $arg
		} elseif {[regexp -nocase {^add ([^ ]+) (.+)$} $text match arg1 arg2]} {
			add_memo $idx $hand $arg1 $arg2
		} elseif {[regexp -nocase {^delete ([^ ]+)$} $text match arg]} {
			delete_memo $idx $arg
		} elseif {[regexp -nocase {^rename ([^ ]+) ([^ ]+)$} $text match arg1 arg2]} {
			rename_memo $idx $arg1 $arg2
		} elseif {[regexp -nocase {^deref ([^ ]+)$} $text match arg]} {
			deref_memo $idx $arg
		} else {
			putdcc $idx "Usage: .memo <query <key>/add <key> <value>/delete <key>/rename <old_key> <new_key>/search <pattern>/deref <key>/list/validate/stats/save/reload>"
			return
		}
		return 1
	}

	proc memo_action {mode nick uhost hand chan text} {
		set now [unixtime]
		if {$chan eq ""} {
			if {($c::ignored_users ne "" && [matchattr $hand $c::ignored_users]) ||
				([info exists v::flood_gate(-)] && ($now - $v::flood_gate(-) < $c::antiflood_delay))} { return }
			set v::flood_gate(-) $now
			set editor [matchattr $hand $c::editor_users]
		} else {
				if {![channel get $chan memo] ||
				($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
				([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))} { return }
			set v::flood_gate($chan) $now
			set editor [matchattr $hand $c::editor_users $chan]
		}

		set clntext [fix_args $text]
		if {$clntext eq ""} {
			if {$editor} {
				sendnotc $nick "Musisz podać hasło, które chcesz przywołać lub edytować."
			} else {
				sendnotc $nick "Musisz podać hasło, które chcesz przywołać."
			}
			return 1
		}
		set argc [llength [split $clntext]]
		set key [strip_codes [get_arg $clntext]]
		set lkey [string tolower $key]
		set known [info exists v::database($lkey)]
		# 1 - query 1 / add/modify 2
		# 2 - append 2
		# 3 - delete 1
		# 4 - rename 2
		# 5 - raw query 1
		# 6 - search (keys) 1
		# 7 - search (vals) 1

		if {$mode == 1 && $argc == 1} {
			if {$known} {
				lassign [get_memo $lkey] when who dbkey dbvalue

				if {$dbvalue eq ""} {
					sendnotc $nick "Hasło \"$key\" jest w bazie, ale wygląda na uszkodzone."
				} else {
					lassign [split $uhost "@"] ident host
					set dbvalue [string map [list "#NICK#" $nick "#IDENT#" $ident "#HOST#" $host "#HAND#" $hand "#CHAN#" $chan "#KEY#" $dbkey "#QUERY#" $key] $dbvalue]
					if {$chan eq ""} {
						sendnotc $nick "$dbkey => $dbvalue"
					} else {
						sendmsg $chan "\[Memo] $dbkey => $dbvalue"
					}
				}
			} else {
				sendnotc $nick "Hasła \"$key\" nie ma jeszcze w bazie."
			}
			return 1
		}

		if {!$editor} {
			sendnotc $nick "Nie posiadasz uprawnień do tworzenia lub edytowania haseł."
			return 1
		}

		if {$argc < 2 && $mode in [list 1 2 4]} {
			sendnotc $nick "Podano za mało argumentów polecenia."
			return 1
		}

		set value [get_str $clntext]

		if {$mode == 1} {
			#if {[regexp {^\{([^ ]+)\}$} $value match alias]} {
			#	set lalias [string tolower $alias]
			#	if {![info exists v::database($lalias)]} {
			#		sendnotc $nick "Nie można tworzyć powiązania z nieistniejącym hasłem."
			#		return 1
			#	}
			#	if {[string equal -nocase $key $alias]} {
			#		sendnotc $nick "Nie można tworzyć powiązania do samego siebie."
			#		return 1
			#	}
			#}
			set v::database($lkey) [list $now $nick $key $value]

			save_database

			if {$known} {
				sendnotc $nick "Hasło \"$key\" zostało zmodyfikowane."
			} else {
				sendnotc $nick "Hasło \"$key\" zostało dodane do bazy."
			}
		} elseif {$mode == 6 || $mode == 7} {
			set data [dict values [array get v::database]]
			set matches [lsearch -nocase -all -inline -index [expr {$mode == 6 ? 2 : 3}] $data $key]
			set cnt [llength $matches]
			if {$cnt == 0} {
				if {$mode == 6} {
					sendnotc $nick "Nie znaleziono haseł pasujących do wzorca \"$key\"."
				} else {
					sendnotc $nick "Nie znaleziono haseł z zawartością pasującą do wzorca \"$key\"."
				}
			} else {
				set shortmatches [lrange [lshuffle [lsubindices $matches 2]] 0 $c::max_matches-1]
				set keys [join [lsort -nocase $shortmatches] ", "]
				if {$cnt != [llength $shortmatches]} {
					append keys ", (...)"
				}
				if {$mode == 6} {
					sendnotc $nick "Hasła pasujące do wzorca \"$key\" ($cnt): $keys"
				} else {
					sendnotc $nick "Hasła z zawartością pasującą do wzorca \"$key\" ($cnt): $keys"
				}
			}
		} else {
			if {!$known} {
				sendnotc $nick "Hasła \"$key\" nie ma jeszcze w bazie."
				return 1
			}

			lassign $v::database($lkey) when who dbkey dbvalue

			switch $mode {
				2	{
						#if {[regexp {^\{[^ ]+\}$} $dbvalue]} {
						#	sendnotc $nick "Hasło \"$key\" jest aliasem - nie można rozszerzać jego definicji w ten sposób."
						#	return 1
						#}
						set v::database($lkey) [list $now $nick $key "$dbvalue $value"]
						sendnotc $nick "Hasło \"$key\" zostało rozszerzone."
						save_database
					}
				3	{
						#if {$refs > 0} {
						#	sendnotc $nick "Do hasła \"$key\" prowadzą inne powiązania - nie można go usunąć."
						#	return 1
						#}
						unset v::database($lkey)
						sendnotc $nick "Hasło \"$key\" zostało usunięte z bazy."
						save_database
					}
				4	{
						set newkey [strip_codes [get_arg $clntext 1]]
						set lnewkey [string tolower $newkey]
						if {![info exists v::database($lnewkey)]} {
							#if {[regexp {^\{([^ ]+)\}$} $dbvalue match alias]} {
							#	if {[string equal -nocase $newkey $alias]} {
							#		sendnotc $nick "Ta zmiana stworzyłaby pętlę - nie można zmienić nazwy."
							#		return 1
							#	}
							#}
							unset v::database($lkey)
							set v::database($lnewkey) [list $now $nick $newkey $dbvalue]
							sendnotc $nick "Hasło \"$key\" zostało przemianowane na \"$newkey\"."
							save_database
						} else {
							sendnotc $nick "Hasło \"$newkey\" jest już w bazie - nie można zmienić nazwy."
							return 1
						}
					}
				5	{
						if {$chan eq ""} {
							sendnotc $nick "$dbkey => $dbvalue"
						} else {
							sendmsg $chan "\[Memo] $dbkey => $dbvalue"
						}
					}
			}
		}
		return 1
	}

	proc get_memo {lkey {redirs 0} {substs 0}} {
		set who [set key [set value ""]]
		set when 0
		if {$redirs > $c::max_redirections} {
			putlog "Memo: key \"$lkey\" reached max redirections"
		} elseif {[info exists v::database($lkey)]} {
			lassign $v::database($lkey) when who key value

			if {[regexp {^\{([^ ]+)\}$} $value match newkey]} {
				incr redirs
				return [get_memo [string tolower $newkey] $redirs $substs]
			}

			while {$substs <= $c::max_substitutions} {
				set tokens [dict values [regexp -all -inline {\{([^ ]+)\}} $value]]
				if {[llength $tokens] == 0} { break }
				foreach token $tokens {
					incr substs
					lassign [get_memo [string tolower $token] $redirs $substs] twhen twho tkey tvalue
					set value [string map -nocase [list "{$token}" $tvalue] $value]
				}
			}

			if {$substs > $c::max_substitutions} {
				putlog "Memo: key \"$lkey\" reached max substitutions"
			}
		}
		return [list $when $who $key $value]
	}

	proc on_pub_cmd_query {nick uhost hand chan text} {
		return [memo_action 1 $nick $uhost $hand $chan $text]
	}

	proc on_prv_cmd_query {nick uhost hand text} {
		return [memo_action 1 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_append {nick uhost hand chan text} {
		return [memo_action 2 $nick $uhost $hand $chan $text]
	}

	proc on_prv_cmd_append {nick uhost hand text} {
		return [memo_action 2 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_delete {nick uhost hand chan text} {
		return [memo_action 3 $nick $uhost $hand $chan $text]
	}

	proc on_prv_cmd_delete {nick uhost hand text} {
		return [memo_action 3 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_rename {nick uhost hand chan text} {
		return [memo_action 4 $nick $uhost $hand $chan $text]
	}

	proc on_prv_cmd_rename {nick uhost hand text} {
		return [memo_action 4 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_query_raw {nick uhost hand chan text} {
		return [memo_action 5 $nick $uhost $hand $chan $text]
	}
	proc on_prv_cmd_query_raw {nick uhost hand text} {
		return [memo_action 5 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_search_key {nick uhost hand chan text} {
		return [memo_action 6 $nick $uhost $hand $chan $text]
	}
	proc on_prv_cmd_search_key {nick uhost hand text} {
		return [memo_action 6 $nick $uhost $hand "" $text]
	}

	proc on_pub_cmd_search_val {nick uhost hand chan text} {
		return [memo_action 7 $nick $uhost $hand $chan $text]
	}
	proc on_prv_cmd_search_val {nick uhost hand text} {
		return [memo_action 7 $nick $uhost $hand "" $text]
	}

	proc load_database {} {
		if {![file exists $c::memo_file] || [file size $c::memo_file] <= 0} { return }

		set file [open $c::memo_file r]
		unset -nocomplain v::database
		array set v::database [gets $file]
		close $file
	}

	proc save_database {} {
		set file [open $c::memo_file w 0600]
		puts $file [array get v::database]
		close $file
	}

	proc on_event_save {event} {
		putlog "Memo: saving database file"
		save_database
		return
	}

	proc search_db {idx pattern} {
		set data [dict values [array get v::database]]

		set matches [lsearch -nocase -all -inline -index 2 $data $pattern]
		set cnt [llength $matches]
		if {$cnt == 0} {
			putdcc $idx "* No keys matching \"$pattern\" found"
		} else {
			set keys [join [lsort -nocase [lsubindices $matches 2]] ", "]
			putdcc $idx "* Keys matching \"$pattern\" ($cnt): $keys"
		}

		set matches [lsearch -nocase -all -inline -index 3 $data $pattern]
		set cnt [llength $matches]
		if {$cnt == 0} {
			putdcc $idx "* No values matching \"$pattern\" found"
		} else {
			set keys [join [lsort -nocase [lsubindices $matches 2]] ", "]
			putdcc $idx "* Keys with values matching \"$pattern\" ($cnt): $keys"
		}
	}

	proc deref_memo {idx key} {
		set key [fix_args [strip_codes $key]]
		set lkey [string tolower $key]
		if {![info exists v::database($lkey)]} {
			putdcc $idx "* Key \"$key\" not found"
		} else {
			set keylist [list]
			foreach ldbkey [array names v::database] {
				lassign $v::database($ldbkey) when who dbkey dbvalue
				if {[string match -nocase "*{$key}*" $dbvalue]} {
					lappend keylist $dbkey
				}
			}

			set cnt [llength $keylist]
			if {$cnt > 0} {
				set keys [join [lsort -nocase $keylist] ", "]
				putdcc $idx "* Keys referring key \"$key\" ($cnt): $keys"
			} else {
				putdcc $idx "* No other keys reference \"$key\" key"
			}
		}
	}

	proc list_memos {idx} {
		if {$c::memo_dump ne ""} { set file [open $c::memo_dump w 0600] }
		foreach key [lsort -nocase [array names v::database]] {
			lassign $v::database($key) when who dbkey dbvalue
			putdcc $idx "* $dbkey => $dbvalue"
			if {$c::memo_dump ne ""} { puts $file "$dbkey => $dbvalue" }
		}
		if {$c::memo_dump ne ""} { close $file }
	}

	proc validate_db {idx} {
		set ok 1
		foreach key [array names v::database] {
			lassign $v::database($key) when who dbkey dbvalue

			set tokens [dict values [regexp -all -inline {\{([^ ]+)\}} $dbvalue]]
			foreach token $tokens {
				if {![info exists v::database([string tolower $token])]} {
					putdcc $idx "* Key \"$dbkey\" links to non-existent key \"$token\""
					set ok 0
				} elseif {[string equal -nocase $token $key]} {
					putdcc $idx "* Key \"$dbkey\" links to itself"
					set ok 0
				}
			}
		}

		if {$ok} {
			putdcc $idx "* No problems detected"
		}
	}

	proc query_db {idx key} {
		set lkey [string tolower $key]
		if {[info exists v::database($lkey)]} {
			lassign $v::database($lkey) when who dbkey dbvalue
			putdcc $idx "* $dbkey => $dbvalue (when: [ctime $when], by: $who)"
		} else {
			putdcc $idx "* Key \"$key\" not found"
		}
	}

	proc add_memo {idx hand key value} {
		set key [fix_args [strip_codes $key]]
		set value [fix_args [strip_codes $value]]
		set lkey [string tolower $key]
		if {[info exists v::database($lkey)]} {
			lassign $v::database($lkey) when who dbkey dbvalue
			putdcc $idx "* Modified \"$key\" (previous content: $dbvalue)"
		} else {
			putdcc $idx "* Added \"$key\""
		}
		set v::database($lkey) [list [unixtime] $hand $key $value]
		save_database
	}

	proc delete_memo {idx key} {
		set key [fix_args [strip_codes $key]]
		set lkey [string tolower $key]
		if {[info exists v::database($lkey)]} {
			unset v::database($lkey)
			putdcc $idx "* Deleted \"$key\""
			save_database
		} else {
			putdcc $idx "* Key \"$key\" not found"
		}
	}

	proc rename_memo {idx oldkey newkey} {
		set oldkey [fix_args [strip_codes $oldkey]]
		set loldkey [string tolower $oldkey]
		set newkey [fix_args [strip_codes $newkey]]
		set lnewkey [string tolower $newkey]
		if {![info exists v::database($loldkey)]} {
			putdcc $idx "* Key \"$oldkey\" not found"
		} elseif {[info exists v::database($lnewkey)]} {
			putdcc $idx "* Key \"$newkey\" already present"
		} else {
			lassign $v::database($loldkey) when who dbkey dbvalue
			unset v::database($loldkey)
			set v::database($lnewkey) [list [unixtime] $who $newkey $dbvalue]
			putdcc $idx "* Key \"$oldkey\" renamed to \"$newkey\""
			save_database
		}
	}

	proc show_stats {idx} {
		set count [llength [array names v::database]]
		set size [string bytelength [array get v::database]]
		set cword [flex $count "memo" "memos" "memos"]
		set sword [flex $size "byte" "bytes" "bytes"]
		putdcc $idx "* Database: $count $cword taking $size $sword"
	}

# -=-=-=-=-=-

	proc init {} {
		variable version; variable author
		set ns [namespace current]

		if {![info exists ::wilk::version]} {
			uplevel #0 source [file dirname [info script]]/wilk.tcl
		}
		namespace import ::wilk::*
		::wilk::register $ns

		setudef flag memo

		load_database

		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_query} ${ns}::on_pub_cmd_query
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_append} ${ns}::on_pub_cmd_append
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_delete} ${ns}::on_pub_cmd_delete
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_rename} ${ns}::on_pub_cmd_rename
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_raw} ${ns}::on_pub_cmd_query_raw
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_search} ${ns}::on_pub_cmd_search_key
		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_vsearch} ${ns}::on_pub_cmd_search_val

		bind msg $c::allowed_prvusers ${c::cmd_name_query} ${ns}::on_prv_cmd_query
		bind msg $c::allowed_prvusers ${c::cmd_name_append} ${ns}::on_prv_cmd_append
		bind msg $c::allowed_prvusers ${c::cmd_name_delete} ${ns}::on_prv_cmd_delete
		bind msg $c::allowed_prvusers ${c::cmd_name_rename} ${ns}::on_prv_cmd_rename
		bind msg $c::allowed_prvusers ${c::cmd_name_raw} ${ns}::on_prv_cmd_query_raw
		bind msg $c::allowed_prvusers ${c::cmd_name_search} ${ns}::on_prv_cmd_search_key
		bind msg $c::allowed_prvusers ${c::cmd_name_vsearch} ${ns}::on_prv_cmd_search_val

		bind evnt - save ${ns}::on_event_save

		bind dcc n|- memo ${ns}::on_dcc_cmd

		putlog "Memo v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_query} ${ns}::on_pub_cmd_query }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_append} ${ns}::on_pub_cmd_append }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_delete} ${ns}::on_pub_cmd_delete }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_rename} ${ns}::on_pub_cmd_rename }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_raw} ${ns}::on_pub_cmd_query_raw }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_search} ${ns}::on_pub_cmd_search_key }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name_vsearch} ${ns}::on_pub_cmd_search_val }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_query} ${ns}::on_prv_cmd_query }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_append} ${ns}::on_prv_cmd_append }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_delete} ${ns}::on_prv_cmd_delete }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_rename} ${ns}::on_prv_cmd_rename }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_raw} ${ns}::on_prv_cmd_query_raw }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_search} ${ns}::on_prv_cmd_search_key }
		catch { unbind msg $c::allowed_prvusers ${c::cmd_name_vsearch} ${ns}::on_prv_cmd_search_val }
		catch { unbind evnt - save ${ns}::on_event_save }
		catch { unbind dcc n|- memo ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag memo
	}

	init
}
