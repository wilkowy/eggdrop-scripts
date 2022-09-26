# Name			Need Help
# Author		wilk wilkowy
# Description	Automated bot requests for op, invite, get key, etc. (similar to getops.tcl or botnetop.tcl)
# Version		1.5 (2018..2021-12-09)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Info:
# - bots/helpers are chosen randomly for each request
# - if use_botnet is 1 then you need to have this script loaded on all bots, but requests are more secure
# - script relies on $botnick == $handle when use_botnet is 1
# - script is designed for IRCnet, but should work on other networks, probably
# - script requires Eggdrop 1.9.x - if you really need a version for old Eggdrop try contacting me

# ToDo: request op after first join?

namespace eval needhelp::c {

# Set to 1 if you have a linked botnet to ask for help through the link instead of /msgs.
variable use_botnet 1

# Request global op (1) or for each channel (0)?
# Using per channel requests allows to spread them across more bots to reduce lags.
variable global_op 0

# If use_botnet == 0, put here a list of bot/session handles to request help from;
# if use_botnet == 1, you can put here a list of session handles to request help from as a fallback if bot gets unlinked (do not use here botnet bots because they use internal passwords, use customized irssi or other bot).
variable helpers [list]

# Password used while requesting help from other sessions.
variable password ""

}

# #################################################################### #

namespace eval needhelp {

	variable version "1.5"
	variable changed "2021-12-09"
	variable author "wilk"

	namespace eval v {
		variable need_ignore 0
		variable spam_flag
	}

	proc helpers_h2n {handles type chan} {
		set helpers [list]
		foreach hand $handles {
			foreach nick [hand2nicks $hand] {
				# We are asking other bots/sessions for help without checking if they are on $chan (isop/onchan is not shared),
				# for op request we check for current @ status and +o flag
				if {$type ne "op" || ([isop $nick $chan] && [matchattr $hand "o|o" $chan])} {
					lappend helpers $nick
				}
			}
		}
		return $helpers
	}

	proc on_need {chan type} {
		# From ircd source:
		# TYPE		ACTION	ONCHAN?	NEEDOP?	FLAG?
		# op		op		+		+		-
		# limit		invite	-		-/+		+R (noops)	ERR_CHANNELISFULL	(limit still blocks)	-server:#channel- nick carries an invitation from nick!ident@host (overriding channel limit).
		# invite	invite	-		+		+I			ERR_INVITEONLYCHAN	(ERR_CHANOPRIVSNEEDED)
		# unban		invite	-		-/+		+e			ERR_BANNEDFROMCHAN	(ban still blocks)		-server:#channel- nick carries an invitation from nick!ident@host (overriding ban on *!*@*).
		# key		key		-		-		-			ERR_BADCHANNELKEY
		# can_join	+b -> +i -> +k -> +l
		if {$type ni [list "op" "limit" "invite" "unban" "key"]} { return }

		set use_botnet $c::use_botnet

		set helpers [list]
		if {$use_botnet} {
			set helpers [helpers_h2n [bots] $type $chan]
			if {[llength $helpers] == 0 && [llength $c::helpers] > 0} {
				set use_botnet 0
			}
		}
		if {!$use_botnet} {
			if {$c::password eq ""} { return }
			set helpers [helpers_h2n $c::helpers $type $chan]
		}
		if {[llength $helpers] == 0} {
			if {![info exists v::spam_flag($chan)] || !$v::spam_flag($chan)} {
				putlog "NeedHelp: bot needs help ($type) on $chan, but no valid helper found (this message will not be repeated)"
			}
			set v::spam_flag($chan) 1
			return
		}
		set v::spam_flag($chan) 0

		set helper [lrandom $helpers]

		set cmd $type
		set appendchan " $chan"
		switch $type {
			"op"		{
							if {$c::global_op} {
								# timer to prevent request flood for every channel
								if {[info exists v::need_ignore] && $v::need_ignore == 1} { return }
								set v::need_ignore 1
								utimer 1 [list set [namespace current]::v::need_ignore 0]
								set appendchan ""
								set problem "bot needs op"
							} else {
								set problem "bot needs op on $chan"
							}
						}
			"limit"		{
							set problem "bot cannot join $chan (+l)"
							if {!$use_botnet} { set cmd "invite" }
						}
			"invite"	{ set problem "bot cannot join $chan (+i)" }
			"unban"		{
							set problem "bot cannot join $chan (+b)"
							if {!$use_botnet} { set cmd "invite" }
						}
			"key"		{ set problem "bot cannot join $chan (+k)" }
		}

		putlog "NeedHelp: $problem - requesting help from $helper"
		if {$use_botnet} {
			putbot $helper "needhelp $cmd $::botnick$appendchan"
		} else {
			sendmsg $helper "$cmd $c::password$appendchan"
		}
	}

	proc on_bot {botnetnick command text} {
		if {$command ne "needhelp"} { return }

		lassign [split $text] type nick chan key
		if {![islinked $botnetnick]} {
			putlog "NeedHelp: $botnetnick requested for help - ignored (bot is not linked)"
			return
		}
		if {$type ni [list "op" "limit" "invite" "unban" "key" "keyrpl"] || ($type eq "keyrpl" && $key eq "")} {
			putlog "NeedHelp: $botnetnick requested for help - ignored (invalid request - $type)"
			return
		}
		if {$chan ne ""} {
			if {![validchan $chan]} {
				putlog "NeedHelp: $botnetnick requested for help - ignored (unknown channel - $chan)"
				return
			}
			if {$type in [list "op" "limit" "invite" "unban"] && ![botisop $chan]} {
				putlog "NeedHelp: $botnetnick requested for help - ignored (this bot is not opped on $chan)"
				return
			}
			if {$type in [list "limit" "invite" "unban" "key"] && [onchan $nick $chan]} {
				putlog "NeedHelp: $botnetnick requested for help - ignored (bot is already on $chan)"
				return
			}
		}
		set hand [nick2hand $nick]
		if {$hand eq "" || $hand eq "*"} {
			putlog "NeedHelp: $botnetnick requested for help - ignored (unknown bot)"
			return
		}
		if {($chan ne "" && ![matchattr $hand "o|o" $chan]) || ![matchattr $hand "o"]} {
			putlog "NeedHelp: $botnetnick requested for help - ignored (unpriviledged bot)"
			return
		}

		switch $type {
			"op"		{
							if {$chan ne ""} {
								if {![onchan $nick $chan]} {
									putlog "NeedHelp: $botnetnick requested for help ($type) - ignored ($botnetnick is not on $chan)"
								} elseif {[isop $nick $chan]} {
									putlog "NeedHelp: $botnetnick requested for help ($type) - ignored ($botnetnick is already opped on $chan)"
								} else {
									putlog "NeedHelp: $botnetnick requested for help ($type) - opping $botnetnick on $chan"
									pushmode $chan "+o" $nick
								}
							} else {
								set chans [list]
								foreach chan [channels] {
									if {[botisop $chan] && [onchan $nick $chan] && ![isop $nick $chan]} {
										lappend chans $chan
										pushmode $chan "+o" $nick
									}
								}
								if {[llength $chans] > 0} {
									putlog "NeedHelp: $botnetnick requested for help ($type) - opping $botnetnick on [join $chans]"
								} else {
									putlog "NeedHelp: $botnetnick requested for help ($type) - unable to help"
								}
							}
						}
			"limit"		-
			"invite"	-
			"unban"		{
							putlog "NeedHelp: $botnetnick requested for help ($type) - inviting $botnetnick on $chan"
							sendinvite $nick $chan
						}
			"key"		{
							set key [getchankey $chan]
							if {$key eq ""} {
								putlog "NeedHelp: $botnetnick requested for help ($type) - ignored ($chan has no channel key)"
							} else {
								putlog "NeedHelp: $botnetnick requested for help ($type) - sending $botnetnick chankey for $chan"
								putbot $nick "needhelp keyrpl $::botnick $chan $key"
							}
						}
			"keyrpl"	{
							if {![botonchan $chan]} {
								putlog "NeedHelp: received channel key from $botnetnick - ignored (this bot is already on $chan)"
							} else {
								putlog "NeedHelp: received channel key from $botnetnick - joining $chan"
								chanjoin $chan $key
							}
						}
		}
	}

	proc on_notice_key {nick uhost hand text dest} {
		if {$c::use_botnet ||
			![isbotnick $dest] ||
			$hand ni $c::helpers ||
			![regexp -nocase {^([^:]+): key is (.+)$} $text match chan key]
		} then { return }
		putlog "NeedHelp: received channel key from $nick - joining $chan"
		chanjoin $chan $key
		return 1
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

		bind need - * ${ns}::on_need

		bind bot - "needhelp" ${ns}::on_bot
		bind notc o|o "*: key is *" ${ns}::on_notice_key

		putlog "NeedHelp v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind need - * ${ns}::on_need }
		catch { unbind bot - "needhelp" ${ns}::on_bot }
		catch { unbind notc o|o "*: key is *" ${ns}::on_notice_key }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
	}

	init
}
