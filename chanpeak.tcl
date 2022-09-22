# Name			ChanPeak
# Author		wilk wilkowy
# Description	Registers channel peak - max nicks on a channel and announces new peak if enabled
# Version		1.1 (2019..2020-01-02)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: chanpeak publicpeak

# Partyline commands: .peak
# .peak info			- display channel peaks
# .peak cleanup			- remove peak data for non existing channels (not in chanlist)
# .peak reset <#>		- reset given channel peak to 0, but keeps "since"
# .peak drop <#>		- remove peak data for given channel
# .peak stats			- display number of entries in database and memory taken
# .peak reload			- reload database
# .peak save			- not really needed, just for the sake

# Channel commands: !peak

# ToDo:
# - use chanset instead? problem with additional infos and keeping data for deleted channels
# - too many hardcoded strings

namespace eval chanpeak::c {

# Users having such flags can trigger channel commands. (use - or -|- to allow all)
variable allowed_users "-|-"

# Users having such flags cannot trigger channel commands. (use "" to disable)
variable ignored_users "I|I"

# Channel command prefix.
variable cmd_prefix "!"

# Channel command name.
variable cmd_name "peak"

# Protect against !peak command floods, in seconds. (0 - off)
variable antiflood_delay 2

# Use this to format time/date.
# To check which placeholders you can use look for strftime function.
# Example: %d.%m.%Y -> 13.10.2019
# Example: %H:%M:%S -> 15:29:34
variable time_format "%d.%m.%Y o %H:%M:%S"

# Chanpeak message. Use *lowercase* channel names! Use * for global default/common message.
# Available placeholders: #NICK#, #CHAN#, #PEAK#, #WHEN#, #PEAKNICK#, #PEAKHOST#, #SINCE#, #HOWOLD#
# Inflected placeholders: #WAS#, #PEAKNICKS#
variable message
set message(*) "Najwięcej osób odwiedziło kanał #CHAN# dnia #WHEN# i #WAS# to \002#PEAK#\002 #PEAKNICKS#. Rekord ustanowiony dzięki #PEAKNICK#."

# Chanpeak public announcement. Use *lowercase* channel names! Use * for global default/common message.
# Available placeholders: #NICK#, #HOST#, #CHAN#, #NEWPEAK#, #PEAK#, #WHEN#, #PEAKNICK#, #PEAKHOST#, #SINCE#, #HOWOLD#
# Inflected placeholders: #ARE#, #NICKS#, #PEAKNICKS#
variable announcement
set announcement(*) "\037Nowy rekord odwiedzin kanału #CHAN# został właśnie ustanowiony dzięki \002#NICK#\002 i #ARE# to \002#NEWPEAK#\002 #NICKS#! Poprzedni rekord był #HOWOLD# temu za sprawą #PEAKNICK#.\037"

# Delay of displaying announcement to prevent message floods, in seconds. (0 - instant)
variable announcement_delay 5

# File that stores all chanpeaks.
variable chanpeak_file "scripts/wilk/chanpeak.db"

}

# #################################################################### #

namespace eval chanpeak {

	variable version "1.1"
	variable changed "2020-01-02"
	variable author "wilk"

	namespace eval v {
		# chan peak when nick uhost since
		variable chanpeak
		variable flood_gate
		variable announcement_timer
	}

	proc on_dcc_cmd {hand idx text} {
		if {$text eq "info"} {
			show_info $idx
		} elseif {$text eq "cleanup"} {
			cleanup_peaks $idx
		} elseif {$text eq "stats"} {
			show_stats $idx
		} elseif {$text eq "save"} {
			save_database
		} elseif {$text eq "reload"} {
			load_database
		} elseif {[regexp -nocase {^reset (.+)$} $text match arg]} {
			reset_peak $idx $arg
		} elseif {[regexp -nocase {^drop (.+)$} $text match arg]} {
			drop_peak $idx $arg
		} else {
			putdcc $idx "Usage: .chanpeak <info/cleanup/reset #/drop #/stats/save/reload>"
			return
		}
		return 1
	}

	proc calc_duration {now then} {
		set diff [expr {$now - $then}]
		set seconds [expr {$diff % 60}]
		set minutes [expr {($diff / 60) % 60}]
		set hours [expr {($diff / 3600) % 24}]
		set days [expr {($diff / 86400) % 7}]
		set weeks [expr {$diff / 604800}]
		set howold [list]
		if {$weeks > 0} {
			lappend howold "$weeks [flex $weeks "tydzień" "tygodnie" "tygodni"]"
		}
		if {$days > 0} {
			lappend howold "$days [flex $days "dzień" "dni" "dni"]"
		}
		if {$hours > 0} {
			lappend howold "$hours [flex $hours "godzinę" "godziny" "godzin"]"
		}
		if {$minutes > 0} {
			lappend howold "$minutes [flex $minutes "minutę" "minuty" "minut"]"
		}
		if {$seconds > 0} {
			lappend howold "$seconds [flex $seconds "sekundę" "sekundy" "sekund"]"
		}
		if {[llength $howold] == 0} {
			lappend howold "0 sekund"
		}
		return [join $howold]
	}

	proc on_join {nick uhost hand chan} {
		set now [unixtime]
		set peak 0
		set since $now
		set lchan [string tolower $chan]
		if {[info exists v::chanpeak($lchan)]} {
			lassign $v::chanpeak($lchan) pchan peak when pnick phost since
		} else {
			set when $now
			set pnick $nick
			set phost $uhost
		}

		set users [llength [chanlist $chan]]
		if {$users <= $peak} { return }

		set v::chanpeak($lchan) [list $chan $users $now $nick $uhost $since]
		save_database

		putlog "ChanPeak: new channel peak ($chan): $peak -> $users"

		if {[channel get $chan publicpeak]} {
			kill_utimer [namespace current]::v::announcement_timer($chan)
			if {$c::announcement_delay > 0} {
				set v::announcement_timer($chan) [utimer $c::announcement_delay [list [namespace current]::show_announcement $chan $users $nick $uhost $peak $when $pnick $phost $since]]
			} elseif {$c::announcement_delay == 0} {
				show_announcement $chan $users $nick $uhost $peak $when $pnick $phost $since
			}
		}
	}

	proc show_announcement {chan users nick uhost peak when pnick phost since} {
		unset -nocomplain v::announcement_timer($chan)

		set lchan [string tolower $chan]
		if {![info exists v::chanpeak($lchan)]} { return }
		if {[info exists c::announcement($lchan)]} {
			set message $c::announcement($lchan)
		} elseif {[info exists c::announcement(*)]} {
			set message $c::announcement(*)
		} else {
			return
		}

		set now [unixtime]
		set fwhen [strftime $c::time_format $when]
		set fsince [strftime $c::time_format $since]
		set are [flex $users "jest" "są" "jest"]
		set nicks [flex $users "nick" "nicki" "nicków"]
		set pnicks [flex $peak "nick" "nicki" "nicków"]
		set howold [calc_duration $now $when]
		sendmsg $chan [string map [list "#NICK#" $nick "#HOST#" $uhost "#CHAN#" $chan "#NEWPEAK#" $users "#PEAK#" $peak "#WHEN#" $fwhen "#PEAKNICK#" $pnick "#PEAKHOST#" $phost "#SINCE#" $fsince "#HOWOLD#" $howold "#ARE#" $are "#NICKS#" $nicks "#PEAKNICKS#" $pnicks] $message]
	}

	proc on_pub_cmd {nick uhost hand chan text} {
		set now [unixtime]
		if {![channel get $chan chanpeak] ||
			($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))} { return }
		set v::flood_gate($chan) $now

		set lchan [string tolower $chan]
		if {![info exists v::chanpeak($lchan)] || [lindex $v::chanpeak($lchan) 1] == 0} {
			sendmsg $chan "Nie posiadam jeszcze statystyk odnośnie tego kanału."
			return 1
		}

		lassign $v::chanpeak($lchan) pchan peak when pnick phost since
		if {[info exists c::message($lchan)]} {
			set message $c::message($lchan)
		} elseif {[info exists c::message(*)]} {
			set message $c::message(*)
		} else {
			return
		}
		set fwhen [strftime $c::time_format $when]
		set fsince [strftime $c::time_format $since]
		set was [flex $peak "był" "były" "było"]
		set pnicks [flex $peak "nick" "nicki" "nicków"]
		set howold [calc_duration $now $when]
		sendmsg $chan [string map [list "#NICK#" $nick "#CHAN#" $pchan "#PEAK#" $peak "#WHEN#" $fwhen "#PEAKNICK#" $pnick "#PEAKHOST#" $phost "#SINCE#" $fsince "#HOWOLD#" $howold "#WAS#" $was "#PEAKNICKS#" $pnicks] $message]
		return 1
	}

	proc load_database {} {
		if {![file exists $c::chanpeak_file] || [file size $c::chanpeak_file] <= 0} { return }

		set file [open $c::chanpeak_file r]
		unset -nocomplain v::chanpeak
		array set v::chanpeak [gets $file]
		close $file
	}

	proc save_database {} {
		set file [open $c::chanpeak_file w 0600]
		puts $file [array get v::chanpeak]
		close $file
	}

	proc on_event_save {event} {
		putlog "ChanPeak: saving database file"
		save_database
		return
	}

	proc reset_peak {idx chan} {
		set lchan [string tolower $chan]
		if {[info exists v::chanpeak($lchan)]} {
			lassign $v::chanpeak($lchan) pchan peak when pnick phost since
			set v::chanpeak($lchan) [list $pchan 0 [unixtime] "-" "-" $since]
			save_database
			putdcc $idx "* Channel $pchan peak reset to 0"
		} else {
			putdcc $idx "* No such channel in database"
		}
	}

	proc drop_peak {idx chan} {
		set lchan [string tolower $chan]
		if {[info exists v::chanpeak($lchan)]} {
			unset v::chanpeak($lchan)
			save_database
			putdcc $idx "* Channel $chan peak removed"
		} else {
			putdcc $idx "* No such channel in database"
		}
	}

	proc cleanup_peaks {idx} {
		set count 0
		foreach chan [array names v::chanpeak] {
			if {![validchan $chan]} {
				unset v::chanpeak($chan)
				incr count
			}
		}
		save_database
		set left [llength [array names v::chanpeak]]
		putdcc $idx "* Removed abandoned channel records: $count, left: $left"
	}

	proc show_info {idx} {
		set now [unixtime]
		foreach lchan [array names v::chanpeak] {
			lassign $v::chanpeak($lchan) chan peak when nick uhost since
			set users ""
			if {![validchan $chan]} {
				putdcc $idx "* Channel $chan: (abandoned)"
			} elseif {[channel get $chan inactive]} {
				putdcc $idx "* Channel $chan: (inactive)"
			} elseif {![botonchan $chan]} {
				putdcc $idx "* Channel $chan: (not on channel)"
			} else {
				putdcc $idx "* Channel $chan:"
				set users " (now: [llength [chanlist $chan]])"
			}
			putdcc $idx "| Peak    : $peak$users"
			putdcc $idx "| Peak by : $nick!$uhost"
			putdcc $idx "| When    : [ctime $when]"
			putdcc $idx "| Since   : [ctime $since]"
		}
	}

	proc show_stats {idx} {
		set count [llength [array names v::chanpeak]]
		set size [string bytelength [array get v::chanpeak]]
		set cword [flex $count "channel" "channels" "channels"]
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

		setudef flag chanpeak
		setudef flag publicpeak

		load_database

		bind join - * ${ns}::on_join

		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name} ${ns}::on_pub_cmd

		bind evnt - save ${ns}::on_event_save

		bind dcc n|- chanpeak ${ns}::on_dcc_cmd

		putlog "ChanPeak v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind join - * ${ns}::on_join }
		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name} ${ns}::on_pub_cmd }
		catch { unbind evnt - save ${ns}::on_event_save }
		catch { unbind dcc n|- chanpeak ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag chanpeak
		deludef flag publicpeak
	}

	init
}
