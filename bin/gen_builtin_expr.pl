#! /usr/bin/env perl

use 5.014;
use warnings;
use experimentals;
use Regexp::Optimizer;

my $builtins;
say Regexp::Optimizer->new->optimize($builtins);

BEGIN {
    $builtins = qr{
            abs
        |   accept
        |   alarm
        |   atan2
        |   bind
        |   binmode
        |   bless
        |   break
        |   caller
        |   chdir
        |   chmod
        |   chomp
        |   chop
        |   chown
        |   chr
        |   chroot
        |   close
        |   closedir
        |   connect
        |   continue
        |   cos
        |   crypt
        |   dbmclose
        |   dbmopen
#        |   default
        |   defined
        |   delete
        |   die
        |   do
        |   dump
        |   each
        |   endgrent
        |   endhostent
        |   endnetent
        |   endprotoent
        |   endpwent
        |   endservent
        |   eof
        |   eval
        |   evalbytes
        |   exec
        |   exists
        |   exit
        |   exp
        |   fc
        |   fcntl
        |   fileno
        |   flock
        |   fork
        |   format
        |   formline
        |   getc
        |   getgrent
        |   getgrgid
        |   getgrnam
        |   gethostbyaddr
        |   gethostbyname
        |   gethostent
        |   getlogin
        |   getnetbyaddr
        |   getnetbyname
        |   getnetent
        |   getpeername
        |   getpgrp
        |   getppid
        |   getpriority
        |   getprotobyname
        |   getprotobynumber
        |   getprotoent
        |   getpwent
        |   getpwnam
        |   getpwuid
        |   getservbyname
        |   getservbyport
        |   getservent
        |   getsockname
        |   getsockopt
#        |   given
        |   glob
        |   gmtime
        |   goto
        |   grep
        |   hex
        |   import
        |   index
        |   int
        |   ioctl
        |   join
        |   keys
        |   kill
        |   last
        |   lc
        |   lcfirst
        |   length
        |   link
        |   listen
        |   local
        |   localtime
        |   lock
        |   log
        |   lstat
        |   map
        |   mkdir
        |   msgctl
        |   msgget
        |   msgrcv
        |   msgsnd
#        |   my
        |   next
#        |   no
        |   oct
        |   open
        |   opendir
        |   ord
#        |   our
        |   pack
        |   package
        |   pipe
        |   pop
        |   pos
        |   print
        |   printf
        |   prototype
        |   push
        |   quotemeta
        |   rand
        |   read
        |   readdir
        |   readline
        |   readlink
        |   readpipe
        |   recv
        |   redo
        |   ref
        |   rename
        |   require
        |   reset
        |   return
        |   reverse
        |   rewinddir
        |   rindex
        |   rmdir
        |   say
        |   scalar
        |   seek
        |   seekdir
        |   select
        |   semctl
        |   semget
        |   semop
        |   send
        |   setgrent
        |   sethostent
        |   setnetent
        |   setpgrp
        |   setpriority
        |   setprotoent
        |   setpwent
        |   setservent
        |   setsockopt
        |   shift
        |   shmctl
        |   shmget
        |   shmread
        |   shmwrite
        |   shutdown
        |   sin
        |   sleep
        |   socket
        |   socketpair
        |   sort
        |   splice
        |   split
        |   sprintf
        |   sqrt
        |   srand
        |   stat
        |   state
        |   study
#        |   sub
        |   substr
        |   symlink
        |   syscall
        |   sysopen
        |   sysread
        |   sysseek
        |   system
        |   syswrite
        |   tell
        |   telldir
        |   tie
        |   tied
        |   time
        |   times
        |   truncate
        |   uc
        |   ucfirst
        |   umask
        |   undef
        |   unlink
        |   unpack
        |   unshift
        |   untie
#        |   use
        |   utime
        |   values
        |   vec
        |   wait
        |   waitpid
        |   wantarray
        |   warn
#        |   when
        |   write
        |   -r        # File is readable by effective uid/gid.
        |   -w        # File is writable by effective uid/gid.
        |   -x        # File is executable by effective uid/gid.
        |   -o        # File is owned by effective uid.
        |   -R        # File is readable by real uid/gid.
        |   -W        # File is writable by real uid/gid.
        |   -X        # File is executable by real uid/gid.
        |   -O        # File is owned by real uid.
        |   -e        # File exists.
        |   -z        # File has zero size (is empty).
        |   -s        # File has nonzero size (returns size in bytes).
        |   -f        # File is a plain file.
        |   -d        # File is a directory.
        |   -l        # File is a symbolic link.
        |   -p        # File is a named pipe (FIFO), or Filehandle is a pipe.
        |   -S        # File is a socket.
        |   -b        # File is a block special file.
        |   -c        # File is a character special file.
        |   -t        # Filehandle is opened to a tty.
        |   -u        # File has setuid bit set.
        |   -g        # File has setgid bit set.
        |   -k        # File has sticky bit set.
        |   -T        # File is an ASCII text file (heuristic guess).
        |   -B        # File is a "binary" file (opposite of ?T).
        |   -M        # Script start time minus file modification time, in days.
        |   -A        # Same for access time.
        |   -C        # Same for inode change time (Unix, may differ for other platforms)
    }x;
}
