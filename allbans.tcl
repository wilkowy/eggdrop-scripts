# Name			AllBans
# Author		wilk wilkowy
# Description	Partyline command to list global bans and all channel bans
# Version		1.0 (2022..2022-06-17)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Partyline commands: .allbans
# .allbans		- list all possible bans
# .allbans b	- brief listing
# .allbans c	- show comments (normally skipped)
# .allbans e	- show ban exempts instead
# .allbans i	- show invites instead

# ToDo:
# - +R (IRCnet)
# - show sticky/unused/old/internal/external only
# - show channel only beIR

namespace eval allbans::c {

# Expiration in seconds to mark ban as soft-perm (here 6 months), use 0 to disable.
#variable softperm 15778463
variable softperm [expr {6 * 30 * 24 * 60 * 60}]
}

# #################################################################### #

namespace eval allbans {

	variable version "1.0"
	variable changed "2022-06-16"
	variable author "wilk"

	proc on_dcc_cmd {hand idx text} {
		set params [split $text]
		set brief [expr {"b" in $params}]
		set showcomments [expr {"c" in $params}]
		set mode [expr {"e" in $params ? 1 : 0}]
		set mode [expr {"i" in $params ? 2 : $mode}]

		set now [unixtime]

		switch $mode {
			2	{ set botgloblist [invitelist] ; set mode_str "invites" }
			1	{ set botgloblist [exemptlist] ; set mode_str "exempts" }
			0	{ set botgloblist [banlist] ; set mode_str "bans" }
		}
		if {[llength $botgloblist] > 0} {
			putdcc $idx "Global $mode_str:"
			foreach data [lsort $botgloblist] {
				lassign $data hostmask comment expires created lastuse creator
				set perm [expr {$expires == 0}]
				#set perm [ispermban $hostmask]
				set softperm [expr {$expires > 0 && $c::softperm > 0 && ($expires - $now) >= $c::softperm}]
				set unused [expr {$lastuse == 0}]
				switch $mode {
					2	{ set sticky [isinvitesticky $hostmask] }
					1	{ set sticky [isexemptsticky $hostmask] }
					0	{ set sticky [isbansticky $hostmask] }
				}
				set active 0
				foreach chan [channels] {
					switch $mode {
						2	{ set active [ischaninvite $hostmask $chan] }
						1	{ set active [ischanexempt $hostmask $chan] }
						0	{ set active [ischanban $hostmask $chan] }
					}
					if {$active} { continue }
				}
				if {!$brief} {
					set text "  $hostmask"
					if {$perm}		{ append text " (perm)" }
					if {$sticky}	{ append text " (sticky)" }
					if {$active}	{ append text " (onchan)" }
					if {$unused}	{ append text " (unused)" }
					putdcc $idx $text
				} else {
					set text "  \["
					if {$perm}		{ append text "P" } else { if {$softperm} { append text "p" } else { append text " " } }
					if {$sticky}	{ append text "S" } else { append text " " }
					if {$unused}	{ append text "U" } else { append text " " }
					if {$active}	{ append text "A" } else { append text " " }
					append text " "
					append text "\] $hostmask"
					putdcc $idx $text
					continue
				}
				set age [expr {($now - $created) / 86400}]
				set text [format "      created: %s (%d day%s ago) by %s" [strftime "%d/%m/%Y %H:%M:%S" $created] $age [expr {$age != 1 ? "s" : ""}] $creator]
				if {!$perm} {
					set age [expr {($expires - $now) / 86400}]
					append text [format ", expires: %s (in %d day%s)" [strftime "%d/%m/%Y %H:%M:%S" $expires] $age [expr {$age != 1 ? "s" : ""}]]
				}
				if {!$unused} {
					set age [expr {($now - $lastuse) / 86400}]
					append text [format ", last use: %s (%d day%s ago)" [strftime "%d/%m/%Y %H:%M:%S" $lastuse] $age [expr {$age != 1 ? "s" : ""}]]
				}
				if {$comment ne "" && $showcomments} {
					append text [format ", reason: %s" $comment]
				}
				putdcc $idx $text
			}
		}

		set chans [channels]
		foreach chan $chans {
			switch $mode {
				2	{ set botchanlist [invitelist $chan] ; set chanlist [chaninvites $chan] }
				1	{ set botchanlist [exemptlist $chan] ; set chanlist [chanexempts $chan] }
				0	{ set botchanlist [banlist $chan] ; set chanlist [chanbans $chan]}
			}
			if {[llength $botchanlist] > 0} {
				putdcc $idx "$chan $mode_str:"
				foreach data [lsort $botchanlist] {
					lassign $data hostmask comment expires created lastuse creator
					set perm [expr {$expires == 0}]
					#set perm [ispermban $hostmask $chan -channel]
					set softperm [expr {$expires > 0 && $c::softperm > 0 && ($expires - $now) >= $c::softperm}]
					set unused [expr {$lastuse == 0}]
					switch $mode {
						2	{
								set global [isinvite $hostmask]
								set sticky [isinvitesticky $hostmask $chan -channel]
								set active [ischaninvite $hostmask $chan]
							}
						1	{
								set global [isexempt $hostmask]
								set sticky [isexemptsticky $hostmask $chan -channel]
								set active [ischanexempt $hostmask $chan]
							}
						0	{
								set global [isban $hostmask]
								set sticky [isbansticky $hostmask $chan -channel]
								set active [ischanban $hostmask $chan]
							}
					}
					if {!$brief} {
						set text "  $hostmask"
						if {$global}	{ append text " (global)" }
						if {$perm}		{ append text " (perm)" }
						if {$sticky}	{ append text " (sticky)" }
						if {$active}	{ append text " (onchan)" }
						if {$unused}	{ append text " (unused)" }
						putdcc $idx $text
					} else {
						set text "  \["
						if {$perm}		{ append text "P" } else { if {$softperm} { append text "p" } else { append text " " } }
						if {$sticky}	{ append text "S" } else { append text " " }
						if {$unused}	{ append text "U" } else { append text " " }
						if {$active}	{ append text "A" } else { append text " " }
						if {$global}	{ append text "G" } else { append text " " }
						append text "\] $hostmask"
						putdcc $idx $text
						continue
					}
					set age [expr {($now - $created) / 86400}]
					set text [format "      created: %s (%d day%s ago) by %s" [strftime "%d/%m/%Y %H:%M:%S" $created] $age [expr {$age != 1 ? "s" : ""}] $creator]
					if {!$perm} {
						set age [expr {($expires - $now) / 86400}]
						append text [format ", expires: %s (in %d day%s)" [strftime "%d/%m/%Y %H:%M:%S" $expires] $age [expr {$age != 1 ? "s" : ""}]]
					}
					if {!$unused} {
						set age [expr {($now - $lastuse) / 86400}]
						append text [format ", last use: %s (%d day%s ago)" [strftime "%d/%m/%Y %H:%M:%S" $lastuse] $age [expr {$age != 1 ? "s" : ""}]]
					}
					if {$active} {
						set chdata [lsearch -inline -exact -index 0 $chanlist $hostmask]
						if {$chdata ne ""} {
							lassign $chdata chhostmask chcreator chage
							if {$chcreator eq "existent"} {
								append text ", set by irc server"
							} else {
								append text [format ", set by %s (%d second%s ago)" $chcreator $chage [expr {$chage != 1 ? "s" : ""}]]
							}
						}
					}
					if {$comment ne "" && $showcomments} {
						append text [format ", reason: %s" $comment]
					}
					putdcc $idx $text
				}
			}
		}

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

		bind dcc n|- allbans ${ns}::on_dcc_cmd

		putlog "AllBans v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind dcc n|- allbans ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
	}

	init
}
