# Topic Update: data->jutro->dzis
# by wilk wilkowy

setudef flag topicupdate

bind evnt - logfile topupd:update

proc topupd:update {type} {
	foreach chan [channels] {
		if {![channel get $chan topicupdate] || ![botisop $chan]} { continue }
		set topic [topic $chan]
		if {$topic eq ""} { continue }
		set update 0
		if {[string match -nocase "*jutro*" $topic]} {
			set topic [string map -nocase {"JUTRO" "DZIS"} $topic]
			regsub -all -nocase -- "\0030?3Nastepn(.+?: dzis )" $topic "\0034Nastepn\\1" topic
			incr update
		}
		set m_day ""
		set m_month ""
		regexp -nocase {(poniedzialek|pon\.|wtorek|wto?\.|srod[ae]|sro?\.|czwartek|czw\.|piatek|pia\.|pt\.|sobot[ae]|sob\.|niedziel[ae]|nie\.|niedz\.) \(([0-9]?[0-9]).([0-9]?[0-9])\)} $topic m_full m_dayname m_day m_month
		if {[string length $m_day] > 0 && [string length $m_month] > 0} {
			set m_month [scan $m_month %d]
			set m_day [scan $m_day %d]
			set p_day [expr {$m_day - 1}]
			set p_month $m_month
			set p_year [strftime %Y]
			if {$p_day == 0} {
				incr p_month -1
				if {$p_month == 0} {
					set p_month 12
					incr p_year -1
				}
				if {$p_month == 2} {
					set p_day 28
					if {([expr {$p_year % 4}] == 0 && [expr {$p_year % 100}] != 0) || [expr {$p_year % 400}] == 0} {
						incr p_day 1
					}
				} elseif {$p_month in [list 1 3 5 7 8 10 12]} {
					set p_day 31
				} else {
					set p_day 30
				}
			}
			set subst ""
			set day [strftime %-d]
			set month [strftime %-m]
			if {$day == $p_day && $month == $p_month} {
				set subst "JUTRO"
			} elseif {$day == $m_day && $month == $m_month} {
				set subst "DZIS"
			}
			if {$subst ne ""} {
				regsub -all -nocase -- {(poniedzialek|pon\.|wtorek|wto?\.|srod[ae]|sro?\.|czwartek|czw\.|piatek|pia\.|pt\.|sobot[ae]|sob\.|niedziel[ae]|nie\.|niedz\.) \([0-9]?[0-9].[0-9]?[0-9]\)} $topic $subst topic
				regsub -all -- "\0030?3Nastepn" $topic "\0034Nastepn" topic
				incr update
			}
		}
		if {$update} {
			putlog "Topic update ($chan): $topic"
			putserv "TOPIC $chan :$topic"
		}
	}
	return
}

putlog "Topic Update v1.4 by wilk"
