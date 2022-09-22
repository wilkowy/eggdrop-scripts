# Name			Public Channel Commands
# Author		wilk wilkowy
# Description	Channel commands to manage a bot
# Version		1.11 (2007..2020-04-24)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: chancmds

# Channel commands: (many, check below and finetune flags)

namespace eval chancmds::c {

# Channel command prefix (to edit command names skip to binds section near the end of this file).
variable cmd_prefix "!"

# Put here *handles* of other bots considered as master bots for this one, while present on channel with @ then this bot will not act.
#/just an idea/ variable master_bots [list]

}

# #################################################################### #

namespace eval chancmds {

	variable version "1.11"
	variable changed "2020-04-24"
	variable author "wilk"

	proc user_voice {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {![botisop $chan]} { return 1 }
		set text [fix_args $text]
		if {$text eq ""} {
			if {![isop $nick $chan] && ![ishalfop $nick $chan] && ![isvoice $nick $chan] && ![matchattr $hand "q|q" $chan]} {
				pushmode $chan "+v" $nick
			}
		} else {
			foreach user [split $text] {
				if {![onchan $user $chan] || [onchansplit $user $chan] || [isop $user $chan] || [ishalfop $user $chan] || [isvoice $user $chan]} { continue }
				set uhand [nick2hand $user $chan]
				if {![matchattr $uhand "q|q" $chan]} {
					pushmode $chan "+v" $user
				}
			}
		}
		return 1
	}

	proc user_rndvoice {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {![botisop $chan]} { return 1 }
		set nicks [list]
		foreach user [chanlist $chan] {
			if {[onchansplit $user $chan] || [isop $user $chan] || [ishalfop $user $chan] || [isvoice $user $chan]} { continue }
			set uhand [nick2hand $user $chan]
			if {![matchattr $uhand "q|q" $chan]} {
				lappend nicks $user
			}
		}
		if {[llength $nicks] > 0} {
			pushmode $chan "+v" [lrandom $nicks]
		}
	}

	proc user_devoice {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {![botisop $chan]} { return 1 }
		set text [fix_args $text]
		if {$text eq ""} {
			if {[isvoice $nick $chan] && ![matchattr $hand "g|g" $chan]} {
				pushmode $chan "-v" $nick
			}
		} else {
			set lvl [get_user_level $hand $chan]
			foreach user [split $text] {
				if {![onchan $user $chan] || [onchansplit $user $chan] || ![isvoice $user $chan]} { continue }
				set uhand [nick2hand $user $chan]
				if {![matchattr $uhand "g|g" $chan] && $lvl >= [get_user_level $uhand $chan]} {
					pushmode $chan "-v" $user
				}
			}
		}
		return 1
	}

	proc user_op {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {![botisop $chan]} { return 1 }
		set text [fix_args $text]
		if {$text eq ""} {
			if {![isop $nick $chan] && ![matchattr $hand "d|d" $chan]} {
				pushmode $chan "+o" $nick
			}
		} else {
			foreach user [split $text] {
				if {![onchan $user $chan] || [onchansplit $user $chan] || [isop $user $chan]} { continue }
				set uhand [nick2hand $user $chan]
				if {![matchattr $uhand "d|d" $chan]} {
					pushmode $chan "+o" $user
				}
			}
		}
		return 1
	}

	proc user_deop {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {![botisop $chan]} { return 1 }
		set text [fix_args $text]
		if {$text eq ""} {
			if {[isop $nick $chan] && ![matchattr $hand "a|a" $chan]} {
				pushmode $chan "-o" $nick
				if {![ishalfop $nick $chan] && ![isvoice $nick $chan] && ![matchattr $hand "q|q" $chan]} {
					pushmode $chan "+v" $nick
				}
			}
		} else {
			set lvl [get_user_level $hand $chan]
			foreach user [split $text] {
				if {![onchan $user $chan] || [onchansplit $user $chan] || [isop $user $chan] || [isbotnick $user]} { continue }
				set uhand [nick2hand $user $chan]
				if {![matchattr $uhand "a|a" $chan] && $lvl >= [get_user_level $uhand $chan]} {
					pushmode $chan "-o" $user
					if {![ishalfop $nick $chan] && ![isvoice $user $chan] && ![matchattr $uhand "q|q" $chan]} {
						pushmode $chan "+v" $nick
					}
				}
			}
		}
		return 1
	}

	proc user_ban {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {![botisop $chan] || $text eq ""} { return 1 }
		set whom [get_arg $text]
		if {[isbotnick $whom]} { return 1 }
		if {[onchan $whom $chan]} {
			if {[get_user_level $hand $chan] >= [get_user_level [nick2hand $whom] $chan]} {
				set mask [maskhost "$whom\![getchanhost $whom $chan]"]
				#set mask "*!*[lindex [split $mask "!"] 1]"
			} else {
				return 1
			}
		} else {
			set mask $whom
		}
		set reason [get_str $text]
		if {$reason ne ""} {
			append reason " - "
		}
		append reason "requested by: $nick"
		newchanban $chan $mask $nick $reason
		return 1
	}

	proc user_kickban {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {![botisop $chan] || $text eq ""} { return 1 }
		set whom [get_arg $text]
		if {![onchan $whom $chan] || [isbotnick $whom] || [onchansplit $whom $chan] || [get_user_level $hand $chan] < [get_user_level [nick2hand $whom] $chan]} { return 1 }
		set mask [maskhost "$whom\![getchanhost $whom $chan]"]
		#set mask "*!*[lindex [split $mask "!"] 1]"
		set reason [get_str $text]
		if {$reason ne ""} {
			append reason " - "
		}
		append reason "requested by: $nick"
		newchanban $chan $mask $nick $reason
		putkick $chan $whom $reason
		return 1
	}

	proc user_unban {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {![botisop $chan] || $text eq ""} { return 1 }
		set mask [get_arg $text]
		if {[ischanban $mask $chan]} {
			killchanban $chan $mask
			#pushmode $chan "-b" $mask
		}
		return 1
	}

	proc user_kick {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {![botisop $chan] || $text eq ""} { return 1 }
		set whom [get_arg $text]
		if {![onchan $whom $chan] || [isbotnick $whom] || [onchansplit $whom $chan] || [get_user_level $hand $chan] < [get_user_level [nick2hand $whom] $chan]} { return 1 }
		set reason [get_str $text]
		if {$reason ne ""} {
			append reason " - "
		}
		append reason "requested by: $nick"
		putkick $chan $whom $reason
		return 1
	}

	proc user_shutup {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {![botisop $chan] || $text eq ""} { return 1 }
		set whom [get_arg $text]
		if {![onchan $whom $chan] || [isbotnick $whom]} { return 1 }
		# && $whom != $nick
		if {![isvoice $nick $chan] && ![isop $nick $chan]} {
			pushmode $chan "+v" $nick
		}
		if {[isvoice $whom $chan]} {
			pushmode $chan "-v" $whom
		}
		if {[isop $whom $chan]} {
			pushmode $chan "-o" $whom
		}
		pushmode $chan "+m"
		return 1
	}

	proc chan_lock {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[botisop $chan]} {
			#putcmdlog "<<$nick>> !$hand! mode $chan +imp"
			pushmode $chan "+i"
			pushmode $chan "+m"
			pushmode $chan "+p"
		}
		return 1
	}

	proc chan_unlock {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[botisop $chan]} {
			pushmode $chan "-i"
			pushmode $chan "-m"
			pushmode $chan "-p"
		}
		return 1
	}

	proc chan_topic {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[botisop $chan] && [fix_args $text] ne ""} {
			settopic $chan $text
		}
		return 1
	}

	proc chan_mode {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {[botisop $chan] && $text ne ""} {
			#set modes [lrange [split $text] 0 6]
			setmodes $chan $text
		}
		return 1
	}

	proc chan_ulimit {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[botisop $chan]} {
			pushmode $chan "-l"
		}
		return 1
	}

	proc bot_rehash {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			rehash
		}
		return 1
	}

	proc bot_restart {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			restart
		}
		return 1
	}

	proc bot_backup {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			backup
		}
		return 1
	}

	proc bot_save {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			save
		}
		return 1
	}

	proc bot_reload {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			reload
		}
		return 1
	}

	proc bot_die {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			set reason [get_str [fix_args $text]]
			if {$reason ne ""} {
				append reason " - "
			}
			append reason "requested by: $nick"
			die $reason
		}
		return 1
	}

	proc bot_jump {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		if {[isop $nick $chan]} {
			set server [get_arg [fix_args $text]]
			if {$server ne ""} {
				jump $server
			}
		}
		return 1
	}

	proc chan_msg {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {$text ne ""} {
			set where [get_arg $text]
			#if {![channel get $where chancmds] || ![botonchan $where]} { return }
			set msg [get_str $text]
			sendmsg $where $msg
		}
		return 1
	}

	proc chan_notice {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {$text ne ""} {
			set where [get_arg $text]
			#if {![channel get $where chancmds] || ![botonchan $where]} { return }
			set msg [get_str $text]
			sendnotc $where $msg
		}
		return 1
	}

	proc chan_action {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		if {$text ne ""} {
			set where [get_arg $text]
			#if {![channel get $where chancmds] || ![botonchan $where]} { return }
			set msg [get_str $text]
			sendact $where $msg
		}
		return 1
	}

	proc misc_os {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set unixtime [unixtime]
		set datetime [strftime "%FT%T%z"]
		set uptime [duration [expr {$unixtime - $::uptime}]]
		set conntime [duration [expr {$unixtime - ${::server-online}}]]
		sendmsg $nick "Eggdrop: \002$::version\002 | TCL: \002$::tcl_version\002 / \002$::tcl_patchLevel\002 | OS: \002[unames]\002 | IRC-server: \002$::server\002 (\002$::serveraddress\002) | Online: \002$conntime\002 | Uptime: \002$uptime\002 | Date: \002$datetime\002 | Epoch: \002$unixtime\002"
		return 1
	}

	proc bot_adduser {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set whom [get_arg [fix_args $text]]
		if {![validuser $whom] && $whom ne ""} {
			adduser $whom
		}
		return 1
	}

	proc bot_deluser {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set whom [get_arg [fix_args $text]]
		if {[validuser $whom]} {
			deluser $whom
		}
		return 1
	}

	proc bot_addhost {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set text [fix_args $text]
		set whom [get_arg $text]
		if {[validuser $whom]} {
			set host [get_arg $text 1]
			if {$host ne ""} {
				setuser $whom HOSTS $host
			}
		}
		return 1
	}

	proc bot_nick {nick uhost hand chan text} {
		if {![channel get $chan chancmds]} { return }
		set ::nick [get_arg [fix_args $text]]
		return 1
	}

	proc get_user_level {hand chan} {
		if {$hand eq "*" || $hand eq ""} { return 0 }
		set lvl 0
		if {[matchattr $hand "v|v" $chan] || [matchattr $hand "g|g" $chan]} { set lvl [expr {$lvl | 0x01}] }
		if {[matchattr $hand "l|l" $chan] || [matchattr $hand "y|y" $chan]} { set lvl [expr {$lvl | 0x02}] }
		if {[matchattr $hand "o|o" $chan] || [matchattr $hand "a|a" $chan]} { set lvl [expr {$lvl | 0x04}] }
		if {[matchattr $hand "-|m" $chan]} { set lvl [expr {$lvl | 0x08}] }
		if {[matchattr $hand "m|-" $chan]} { set lvl [expr {$lvl | 0x10}] }
		if {[matchattr $hand "-|n" $chan]} { set lvl [expr {$lvl | 0x20}] }
		if {[matchattr $hand "n|-" $chan]} { set lvl [expr {$lvl | 0x40}] }
		if {[matchattr $hand "f|f" $chan]} { set lvl [expr {$lvl | 0x80}] }
		return $lvl
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

		setudef flag chancmds

		bind pub m|m +o ${ns}::user_op
		bind pub m|m ${c::cmd_prefix}o ${ns}::user_op
		bind pub m|m ${c::cmd_prefix}op ${ns}::user_op
		bind pub m|m -o ${ns}::user_deop
		bind pub m|m ${c::cmd_prefix}do ${ns}::user_deop
		bind pub m|m ${c::cmd_prefix}deop ${ns}::user_deop

		bind pub v|v +v ${ns}::user_voice
		bind pub v|v ${c::cmd_prefix}v ${ns}::user_voice
		bind pub v|v ${c::cmd_prefix}voice ${ns}::user_voice
		bind pub v|v ${c::cmd_prefix}rv ${ns}::user_rndvoice
		bind pub v|v ${c::cmd_prefix}rvoice ${ns}::user_rndvoice
		bind pub v|v -v ${ns}::user_devoice
		bind pub v|v ${c::cmd_prefix}dv ${ns}::user_devoice
		bind pub v|v ${c::cmd_prefix}devoice ${ns}::user_devoice

		#bind pub o|o ${c::cmd_prefix}k ${ns}::user_kick
		bind pub o|o ${c::cmd_prefix}kick ${ns}::user_kick
		#bind pub m|m ${c::cmd_prefix}b ${ns}::user_ban
		bind pub m|m ${c::cmd_prefix}ban ${ns}::user_ban
		#bind pub m|m ${c::cmd_prefix}kb ${ns}::user_kickban
		bind pub m|m ${c::cmd_prefix}kickban ${ns}::user_kickban
		#bind pub m|m ${c::cmd_prefix}ub ${ns}::user_unban
		bind pub m|m ${c::cmd_prefix}unban ${ns}::user_unban

		bind pub m|m ${c::cmd_prefix}shutup ${ns}::user_shutup
		bind pub m|m ${c::cmd_prefix}silence ${ns}::user_shutup
		bind pub m|m ${c::cmd_prefix}quiet ${ns}::user_shutup
		bind pub m|m ${c::cmd_prefix}stfu ${ns}::user_shutup

		bind pub o|o ${c::cmd_prefix}msg ${ns}::chan_msg
		bind pub o|o ${c::cmd_prefix}say ${ns}::chan_msg
		bind pub o|o ${c::cmd_prefix}notice ${ns}::chan_notice
		bind pub o|o ${c::cmd_prefix}me ${ns}::chan_action

		bind pub v|v ${c::cmd_prefix}t ${ns}::chan_topic
		bind pub v|v ${c::cmd_prefix}topic ${ns}::chan_topic

		bind pub n|n ${c::cmd_prefix}mode ${ns}::chan_mode

		bind pub m|m -l ${ns}::chan_ulimit
		#bind pub m|m ${c::cmd_prefix}ul ${ns}::chan_ulimit
		bind pub m|m ${c::cmd_prefix}ulimit ${ns}::chan_ulimit
		bind pub m|m ${c::cmd_prefix}unlimit ${ns}::chan_ulimit

		#bind pub n|n ${c::cmd_prefix}cl ${ns}::chan_lock
		bind pub n|n ${c::cmd_prefix}lock ${ns}::chan_lock
		#bind pub n|n ${c::cmd_prefix}cu ${ns}::chan_unlock
		bind pub n|n ${c::cmd_prefix}unlock ${ns}::chan_unlock

		bind pub n|- ${c::cmd_prefix}adduser ${ns}::bot_adduser
		bind pub n|- ${c::cmd_prefix}deluser ${ns}::bot_deluser
		bind pub n|- ${c::cmd_prefix}addhost ${ns}::bot_addhost

		bind pub n|- ${c::cmd_prefix}nick ${ns}::bot_nick

		bind pub m|- ${c::cmd_prefix}rehash ${ns}::bot_rehash
		bind pub n|- ${c::cmd_prefix}restart ${ns}::bot_restart
		bind pub n|- ${c::cmd_prefix}reload ${ns}::bot_reload
		bind pub m|- ${c::cmd_prefix}save ${ns}::bot_save
		bind pub n|- ${c::cmd_prefix}backup ${ns}::bot_backup

		bind pub n|n ${c::cmd_prefix}jump ${ns}::bot_jump

		bind pub n|- ${c::cmd_prefix}die ${ns}::bot_die

		bind pub n|- ${c::cmd_prefix}os ${ns}::misc_os

		putlog "ChanCmds v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind pub m|m +o ${ns}::user_op }
		catch { unbind pub m|m ${c::cmd_prefix}o ${ns}::user_op }
		catch { unbind pub m|m ${c::cmd_prefix}op ${ns}::user_op }
		catch { unbind pub m|m -o ${ns}::user_deop }
		catch { unbind pub m|m ${c::cmd_prefix}do ${ns}::user_deop }
		catch { unbind pub m|m ${c::cmd_prefix}deop ${ns}::user_deop }

		catch { unbind pub v|v +v ${ns}::user_voice }
		catch { unbind pub v|v ${c::cmd_prefix}v ${ns}::user_voice }
		catch { unbind pub v|v ${c::cmd_prefix}voice ${ns}::user_voice }
		catch { unbind pub v|v ${c::cmd_prefix}rv ${ns}::user_rndvoice }
		catch { unbind pub v|v ${c::cmd_prefix}rvoice ${ns}::user_rndvoice }
		catch { unbind pub v|v -v ${ns}::user_devoice }
		catch { unbind pub v|v ${c::cmd_prefix}dv ${ns}::user_devoice }
		catch { unbind pub v|v ${c::cmd_prefix}devoice ${ns}::user_devoice }

		catch { unbind pub o|o ${c::cmd_prefix}k ${ns}::user_kick }
		catch { unbind pub o|o ${c::cmd_prefix}kick ${ns}::user_kick }
		catch { unbind pub m|m ${c::cmd_prefix}b ${ns}::user_ban }
		catch { unbind pub m|m ${c::cmd_prefix}ban ${ns}::user_ban }
		catch { unbind pub m|m ${c::cmd_prefix}kb ${ns}::user_kickban }
		catch { unbind pub m|m ${c::cmd_prefix}kickban ${ns}::user_kickban }
		catch { unbind pub m|m ${c::cmd_prefix}ub ${ns}::user_unban }
		catch { unbind pub m|m ${c::cmd_prefix}unban ${ns}::user_unban }

		catch { unbind pub m|m ${c::cmd_prefix}shutup ${ns}::user_shutup }
		catch { unbind pub m|m ${c::cmd_prefix}silence ${ns}::user_shutup }
		catch { unbind pub m|m ${c::cmd_prefix}quiet ${ns}::user_shutup }
		catch { unbind pub m|m ${c::cmd_prefix}stfu ${ns}::user_shutup }

		catch { unbind pub o|o ${c::cmd_prefix}msg ${ns}::chan_msg }
		catch { unbind pub o|o ${c::cmd_prefix}say ${ns}::chan_msg }
		catch { unbind pub o|o ${c::cmd_prefix}notice ${ns}::chan_notice }
		catch { unbind pub o|o ${c::cmd_prefix}me ${ns}::chan_action }

		catch { unbind pub v|v ${c::cmd_prefix}t ${ns}::chan_topic }
		catch { unbind pub v|v ${c::cmd_prefix}topic ${ns}::chan_topic }

		catch { unbind pub n|n ${c::cmd_prefix}mode ${ns}::chan_mode }

		catch { unbind pub m|m -l ${ns}::chan_ulimit }
		catch { unbind pub m|m ${c::cmd_prefix}ul ${ns}::chan_ulimit }
		catch { unbind pub m|m ${c::cmd_prefix}ulimit ${ns}::chan_ulimit }
		catch { unbind pub m|m ${c::cmd_prefix}unlimit ${ns}::chan_ulimit }

		catch { unbind pub n|n ${c::cmd_prefix}cl ${ns}::chan_lock }
		catch { unbind pub n|n ${c::cmd_prefix}lock ${ns}::chan_lock }
		catch { unbind pub n|n ${c::cmd_prefix}cu ${ns}::chan_unlock }
		catch { unbind pub n|n ${c::cmd_prefix}unlock ${ns}::chan_unlock }

		catch { unbind pub n|- ${c::cmd_prefix}adduser ${ns}::bot_adduser }
		catch { unbind pub n|- ${c::cmd_prefix}deluser ${ns}::bot_deluser }
		catch { unbind pub n|- ${c::cmd_prefix}addhost ${ns}::bot_addhost }

		catch { unbind pub n|- ${c::cmd_prefix}nick ${ns}::bot_nick }

		catch { unbind pub m|- ${c::cmd_prefix}rehash ${ns}::bot_rehash }
		catch { unbind pub n|- ${c::cmd_prefix}restart ${ns}::bot_restart }
		catch { unbind pub n|- ${c::cmd_prefix}reload ${ns}::bot_reload }
		catch { unbind pub m|- ${c::cmd_prefix}save ${ns}::bot_save }
		catch { unbind pub n|- ${c::cmd_prefix}backup ${ns}::bot_backup }

		catch { unbind pub n|n ${c::cmd_prefix}jump ${ns}::bot_jump }

		catch { unbind pub n|- ${c::cmd_prefix}die ${ns}::bot_die }

		catch { unbind pub n|- ${c::cmd_prefix}os ${ns}::misc_os }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag chancmds
	}

	init
}
