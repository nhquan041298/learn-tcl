#!/bin/sh

#\
exec tclsh "$0" ${1+"$@"}

proc READ_FILE { {FILE_NAME} } {
    set chk [file exists $FILE_NAME]
    if {$chk==0} {
        puts "* ERROR: $FILE_NAME not found."
        return -1
    }

    set fid [open $FILE_NAME]
    set CHECK_LIST {}
    while {[gets $fid str]>=0} {
        lappend CHECK_LIST $str
    }
    close $fid
    return $CHECK_LIST
}

