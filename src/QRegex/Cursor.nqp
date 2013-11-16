# Some things that all cursors involved in a given parse share.
my class ParseShared is export {
    has $!orig;
    has str $!target;
    has int $!highwater;
    has @!highexpect;
    has %!marks;
    has $!fail_cursor;
    has $!ACTIONS;
    
    # Follow is a little simple usage tracing infrastructure, used by the
    # !cursor_start_* methods when uncommented.
    my %cursors_created;
    my $cursors_total;
    method log_cc($name) {
        %cursors_created{$name}++;
        $cursors_total++;
    }
    method log_dump() {
        for %cursors_created {
            say($_.value ~ "\t" ~ $_.key);
        }
        say("TOTAL: " ~ $cursors_total);
    }
}

role NQPCursorRole is export {
    has $!shared;
    has int $!from;
    has int $!pos;
    has $!match;
    has $!name;
    has $!bstack;
    has $!cstack;
    has $!regexsub;
    has $!restart;

    method orig() { nqp::getattr($!shared, ParseShared, '$!orig') }
    method target() { nqp::getattr_s($!shared, ParseShared, '$!target') }
    method from() { $!from }
    method pos() { $!pos }

    method update_actions() { nqp::bindattr($!shared, ParseShared, '$!ACTIONS', $*ACTIONS) }

    my $NO_CAPS := nqp::hash();
    method CAPHASH() {
        my $caps    := nqp::hash();
        my %caplist := $NO_CAPS;
        my $iter;
        my str $curcap;
        my $cs;
        my int $csi;
        my int $cselems;
        my $subcur;
        my $submatch;
        my $name;
        
        if !nqp::isnull($!regexsub) && nqp::defined($!regexsub) {
            %caplist := nqp::can($!regexsub, 'CAPS') ?? $!regexsub.CAPS() !! nqp::null();
            if !nqp::isnull(%caplist) && %caplist {
                $iter := nqp::iterator(%caplist);
                while $iter {
                    $curcap := nqp::iterkey_s(nqp::shift($iter));
                    $caps{$curcap} := nqp::list() if nqp::atkey(%caplist, $curcap) >= 2;
                }
            }
        }
        if !nqp::isnull($!cstack) && $!cstack {
            $cs      := $!cstack;
            $cselems := nqp::elems($cs);
            while $csi < $cselems {
                $subcur := nqp::atpos($cs, $csi);
                $submatch := $subcur.MATCH;
                $name := nqp::getattr($subcur, $?CLASS, '$!name');
                if !nqp::isnull($name) && nqp::defined($name) {
                    if nqp::index($name, '=') < 0 {
                        %caplist{$name} >= 2
                            ?? nqp::push($caps{$name}, $submatch)
                            !! nqp::bindkey($caps, $name, $submatch);
                    }
                    else {
                        for nqp::split('=', $name) -> $name {
                            %caplist{$name} >= 2
                                ?? nqp::push($caps{$name}, $submatch)
                                !! nqp::bindkey($caps, $name, $submatch);
                        }
                    }
                }
                $csi++;
            }
        } 
        $caps;
    }

    method !cursor_init($orig, :$p = 0, :$c, :$shared) {
        my $new := self.CREATE();
        unless $shared {
            $shared := nqp::create(ParseShared);
            nqp::bindattr($shared, ParseShared, '$!orig', $orig);
            nqp::bindattr_s($shared, ParseShared, '$!target',
#?if parrot
                pir::trans_encoding__Ssi($orig, pir::find_encoding__Is('ucs4')));
#?endif
#?if !parrot
                $orig);
#?endif
            nqp::bindattr_i($shared, ParseShared, '$!highwater', 0);
            nqp::bindattr($shared, ParseShared, '@!highexpect', nqp::list_s());
            nqp::bindattr($shared, ParseShared, '%!marks', nqp::hash());
        }
        nqp::bindattr($new, $?CLASS, '$!shared', $shared);
        if nqp::defined($c) {
            nqp::bindattr_i($new, $?CLASS, '$!from', -1);
            nqp::bindattr_i($new, $?CLASS, '$!pos', $c);
        }
        else {
            nqp::bindattr_i($new, $?CLASS, '$!from', $p);
            nqp::bindattr_i($new, $?CLASS, '$!pos', $p);
        }
        nqp::bindattr($shared, ParseShared, '$!fail_cursor', $new.'!cursor_start_cur'());
        $new.update_actions();
        $new;
    }
    
    # Starts a new Cursor, returning all information relating to it in an array.
    # The array is valid until the next call to !cursor_start_all.
    my $NO_RESTART := 0;
    my $RESTART := 1;
    method !cursor_start_all() {
        my @start_result;
        my $new := nqp::create(self);
        my $sub := nqp::callercode();
        # Uncomment following to log cursor creation.
        #$!shared.log_cc(nqp::getcodename($sub));
        nqp::bindattr($new, $?CLASS, '$!shared', $!shared);
        nqp::bindattr($new, $?CLASS, '$!regexsub', nqp::ifnull(nqp::getcodeobj($sub), $sub));
        if nqp::defined($!restart) {
            nqp::bindattr_i($new, $?CLASS, '$!pos', $!pos);
            nqp::bindattr($new, $?CLASS, '$!cstack', nqp::clone($!cstack)) if $!cstack;
            nqp::bindpos(@start_result, 0, $new);
            nqp::bindpos(@start_result, 1, nqp::getattr_s($!shared, ParseShared, '$!target'));
            nqp::bindpos(@start_result, 2, nqp::bindattr_i($new, $?CLASS, '$!from', $!from));
            nqp::bindpos(@start_result, 3, $?CLASS);
            nqp::bindpos(@start_result, 4, nqp::bindattr($new, $?CLASS, '$!bstack', nqp::clone($!bstack)));
            nqp::bindpos(@start_result, 5, $RESTART);
            @start_result
        }
        else {
            nqp::bindattr_i($new, $?CLASS, '$!pos', -3);
            nqp::bindpos(@start_result, 0, $new);
            nqp::bindpos(@start_result, 1, nqp::getattr_s($!shared, ParseShared, '$!target'));
            nqp::bindpos(@start_result, 2, nqp::bindattr_i($new, $?CLASS, '$!from', $!pos));
            nqp::bindpos(@start_result, 3, $?CLASS);
            nqp::bindpos(@start_result, 4, nqp::bindattr($new, $?CLASS, '$!bstack', nqp::list_i()));
            nqp::bindpos(@start_result, 5, $NO_RESTART);
            @start_result
        }
    }
    
    # Starts a new cursor, returning nothing but the cursor.
    method !cursor_start_cur() {
        my $new := nqp::create(self);
        my $sub := nqp::callercode();
        # Uncomment following to log cursor creation.
        #$!shared.log_cc(nqp::getcodename($sub));
        nqp::bindattr($new, $?CLASS, '$!shared', $!shared);
        nqp::bindattr($new, $?CLASS, '$!regexsub', nqp::ifnull(nqp::getcodeobj($sub), $sub));
        if nqp::defined($!restart) {
            nqp::die("!cursor_start_cur cannot restart a cursor");
        }
        nqp::bindattr_i($new, $?CLASS, '$!pos', -3);
        nqp::bindattr_i($new, $?CLASS, '$!from', $!pos);
        nqp::bindattr($new, $?CLASS, '$!bstack', nqp::list_i());
        $new
    }
    
    method !cursor_start_fail() {
        nqp::getattr($!shared, ParseShared, '$!fail_cursor');
    }

    method !cursor_start_subcapture($from) {
        my $new := nqp::create(self);
        nqp::bindattr($new, $?CLASS, '$!shared', $!shared);
        nqp::bindattr_i($new, $?CLASS, '$!from', $from);
        nqp::bindattr_i($new, $?CLASS, '$!pos', -3);
        $new;
    }

    method !cursor_capture($capture, $name) {
        $!match  := nqp::null();
        $!cstack := [] unless nqp::defined($!cstack);
        nqp::push($!cstack, $capture);
        nqp::bindattr($capture, $?CLASS, '$!name', $name);
        nqp::push_i($!bstack, 0);
        nqp::push_i($!bstack, $!pos);
        nqp::push_i($!bstack, 0);
        nqp::push_i($!bstack, nqp::elems($!cstack));
        $!cstack;
    }
    
    method !cursor_push_cstack($capture) {
        $!cstack := [] unless nqp::defined($!cstack);
        nqp::push($!cstack, $capture);
        $!cstack;
    }

    my $pass_mark := 1; # NQP has no constant table yet
    method !cursor_pass(int $pos, $name?, :$backtrack) {
        $!match := $pass_mark;
        $!pos := $pos;
        $!restart := $!regexsub
            if $backtrack;
        $!bstack := nqp::null()
            unless $backtrack;
        self.'!reduce'($name) if $name;
    }

    method !cursor_fail() {
        $!match  := nqp::null();
        $!bstack := nqp::null();
        $!pos    := -3;
    }
    
    method !cursor_pos(int $pos) {
        $!pos := $pos;
    }

    method !cursor_next() {
        if nqp::defined($!restart) {
            $!restart(self);
        }
        else {
            my $cur := self."!cursor_start_cur"();
            $cur."!cursor_fail"();
            $cur
        }
    }

    method !cursor_more(*%opts) {
        return self."!cursor_next"() if %opts<ex>;
        my $new := self.CREATE();
        nqp::bindattr($new, $?CLASS, '$!shared', $!shared);
        nqp::bindattr_i($new, $?CLASS, '$!from', -1);
        nqp::bindattr_i($new, $?CLASS, '$!pos',
            (%opts<ov> || $!from >= $!pos) ?? $!from+1 !! $!pos);
        $!regexsub($new);
    }

    method !reduce(str $name) {
        my $actions := nqp::getattr($!shared, ParseShared, '$!ACTIONS');
        #my $actions := nqp::getlexdyn('$*ACTIONS');
        nqp::die("the actions got desync'd in $name") unless $actions =:= $*ACTIONS;
        nqp::findmethod($actions, $name)($actions, self.MATCH)
            if !nqp::isnull($actions) && nqp::can($actions, $name);
    }

    method !reduce_with_match($name, $key, $match) {
        my $actions := nqp::getattr($!shared, ParseShared, '$!ACTIONS');
        nqp::die("the actions got desync'd in $name") unless $actions =:= $*ACTIONS;
        #my $actions := nqp::getlexdyn('$*ACTIONS');
        nqp::findmethod($actions, $name)($actions, $match, $key)
            if !nqp::isnull($actions) && nqp::can($actions, $name);
    }
    
    method !shared() { $!shared }

    my @EMPTY := [];
    method !protoregex($name) {
        # Obtain and run NFA.
        my $shared := $!shared;
        my $nfa := self.HOW.cache(self, $name, { self.'!protoregex_nfa'($name) });
        my @fates := $nfa.run(nqp::getattr_s($shared, ParseShared, '$!target'), $!pos);
        
        # Update highwater mark.
        my int $highwater := nqp::getattr_i($shared, ParseShared, '$!highwater');
        if $!pos > $highwater {
            nqp::bindattr_i($shared, ParseShared, '$!highwater', $!pos);
        }
        
        # Visit rules in fate order.
        my @rxfate := $nfa.states[0];
        my $cur;
        my $rxname;
        while @fates {
            $rxname := nqp::atpos(@rxfate, nqp::pop_i(@fates));
            #nqp::say("invoking $rxname");
            $cur := self."$rxname"();
            @fates := @EMPTY if nqp::getattr_i($cur, $?CLASS, '$!pos') >= 0;
        }
        $cur // nqp::getattr($shared, ParseShared, '$!fail_cursor');
    }

    method !protoregex_nfa($name) {
        my %protorx := self.HOW.cache(self, "!protoregex_table", { self."!protoregex_table"() });
        my $nfa := QRegex::NFA.new;
        my @fates := $nfa.states[0];
        my int $start := 1;
        my int $fate := 0;
        if nqp::existskey(%protorx, $name) {
            for %protorx{$name} -> $rxname {
                $fate := $fate + 1;
                @fates[$fate] := $rxname;
                $nfa.mergesubrule($start, 0, $fate, self, $rxname);
            }
        }
        $nfa;
    }

    method !protoregex_table() {
        my %protorx;
        for self.HOW.methods(self) -> $meth {
            my str $methname := $meth.name();
            my int $sympos   := nqp::index($methname, ':');
            if $sympos > 0 {
                my str $prefix := nqp::substr($methname, 0, $sympos);
                %protorx{$prefix} := [] unless nqp::existskey(%protorx, $prefix);
                nqp::push(%protorx{$prefix}, $methname);
            }
        }
        %protorx;
    }

    method !alt(int $pos, str $name, @labels = []) {
        # Update highwater mark.
        my $shared := $!shared;
        my int $highwater := nqp::getattr_i($shared, ParseShared, '$!highwater');
        if $pos > $highwater {
            nqp::bindattr_i($shared, ParseShared, '$!highwater', $pos);
        }
        
        # Evaluate the alternation.
        my $nfa := self.HOW.cache(self, $name, { self.'!alt_nfa'($!regexsub, $name) });
        $nfa.run_alt(nqp::getattr_s($shared, ParseShared, '$!target'), $pos, $!bstack, $!cstack, @labels);
    }

    method !alt_nfa($regex, str $name) {
        my $nfa := QRegex::NFA.new;
        my @fates := $nfa.states[0];
        my int $start := 1;
        my int $fate := 0;
        for $regex.ALT_NFA($name) {
            @fates[$fate] := $fate;
            $nfa.mergesubstates($start, 0, $fate, $_, self);
            $fate++;
        }
        $nfa
    }

    method !precompute_nfas() {
        # Pre-compute all of the proto-regex NFAs.
        my %protorx := self.HOW.cache(self, "!protoregex_table", { self."!protoregex_table"() });
        for %protorx {
            self.HOW.cache(self, $_.key, { self.'!protoregex_nfa'($_.key) });
        }

        # Pre-compute all the alternation NFAs.
        sub precomp_alt_nfas($meth) {
            if nqp::can($meth, 'ALT_NFAS') {
                for $meth.ALT_NFAS -> $name {
                    self.HOW.cache(self, $name, { self.'!alt_nfa'($meth, $name.key) });
                }
            }
        }
        for self.HOW.methods(self) -> $meth {
            precomp_alt_nfas($meth);
            if nqp::can($meth, 'NESTED_CODES') {
                for $meth.NESTED_CODES -> $code {
                    precomp_alt_nfas($code);
                }
            }
        }
    }
    
    method !dba(int $pos, str $dba) {
        my $shared := $!shared;
        my int $highwater := nqp::getattr_i($shared, ParseShared, '$!highwater');
        my $highexpect;
        if $pos >= $highwater {
            $highexpect := nqp::getattr($shared, ParseShared, '@!highexpect');
            if $pos > $highwater {
                nqp::setelems($highexpect, 0);
                nqp::bindattr_i($shared, ParseShared, '$!highwater', $pos);
            }
            nqp::push_s($highexpect, $dba);
        }
    }
    
    method !highwater() {
        nqp::getattr_i($!shared, ParseShared, '$!highwater')
    }
    
    method !highexpect() {
        nqp::getattr($!shared, ParseShared, '@!highexpect')
    }
    
    method !fresh_highexpect() {
        my @old := nqp::getattr($!shared, ParseShared, '@!highexpect');
        nqp::bindattr($!shared, ParseShared, '@!highexpect', nqp::list_s());
        @old
    }
    
    method !set_highexpect(@highexpect) {
        nqp::bindattr($!shared, ParseShared, '@!highexpect', @highexpect)
    }
    
    method !clear_highwater() {
        my $highexpect := nqp::getattr($!shared, ParseShared, '@!highexpect');
        nqp::setelems($highexpect, 0);
        nqp::bindattr_i($!shared, ParseShared, '$!highwater', -1)
    }

    method !BACKREF($name) {
        my $cur   := self."!cursor_start_cur"();
        my int $n := $!cstack ?? nqp::elems($!cstack) - 1 !! -1;
        $n-- while $n >= 0 && (nqp::isnull(nqp::getattr($!cstack[$n], $?CLASS, '$!name')) ||
                               nqp::getattr($!cstack[$n], $?CLASS, '$!name') ne $name);
        if $n >= 0 {
            my $subcur := $!cstack[$n];
            my int $litlen := $subcur.pos - $subcur.from;
            my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
            $cur."!cursor_pass"($!pos + $litlen, '')
              if nqp::substr($target, $!pos, $litlen) 
                   eq nqp::substr($target, $subcur.from, $litlen);
        }
        $cur;
    }

    method !LITERAL(str $str, int $i = 0) {
        my $cur;
        my int $litlen := nqp::chars($str);
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        if $litlen < 1 ||
            ($i ?? nqp::lc(nqp::substr($target, $!pos, $litlen)) eq nqp::lc($str)
                !! nqp::substr($target, $!pos, $litlen) eq $str) {
            $cur := self."!cursor_start_cur"();
            $cur."!cursor_pass"($!pos + $litlen);
        }
        else {
            $cur := nqp::getattr($!shared, ParseShared, '$!fail_cursor');
        }
        $cur;
    }

    method at($pos) {
        my $cur := self."!cursor_start_cur"();
        $cur."!cursor_pass"($!pos) if +$pos == $!pos;
        $cur;
    }

    method before($regex) {
        my int $orig_highwater := nqp::getattr_i($!shared, ParseShared, '$!highwater');
        my $orig_highexpect := nqp::getattr($!shared, ParseShared, '@!highexpect');
        nqp::bindattr($!shared, ParseShared, '@!highexpect', nqp::list_s());
        my $cur := self."!cursor_start_cur"();
        nqp::bindattr_i($cur, $?CLASS, '$!pos', $!pos);
        nqp::getattr_i($regex($cur), $?CLASS, '$!pos') >= 0 ??
            $cur."!cursor_pass"($!pos, 'before') !!
            nqp::bindattr_i($cur, $?CLASS, '$!pos', -3);
        nqp::bindattr_i($!shared, ParseShared, '$!highwater', $orig_highwater);
        nqp::bindattr($!shared, ParseShared, '@!highexpect', $orig_highexpect);
        $cur;
    }

    # Expects to get a regex whose syntax tree was flipped during the
    # compile.
    method after($regex) {
        my int $orig_highwater := nqp::getattr_i($!shared, ParseShared, '$!highwater');
        my $orig_highexpect := nqp::getattr($!shared, ParseShared, '@!highexpect');
        nqp::bindattr($!shared, ParseShared, '@!highexpect', nqp::list_s());
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        my $shared := nqp::clone($!shared);
        nqp::bindattr_s($shared, ParseShared, '$!target', nqp::flip($target));
        nqp::bindattr($cur, $?CLASS, '$!shared', $shared);
        nqp::bindattr_i($cur, $?CLASS, '$!from', nqp::chars($target) - $!pos);
        nqp::bindattr_i($cur, $?CLASS, '$!pos', nqp::chars($target) - $!pos);
        nqp::getattr_i($regex($cur), $?CLASS, '$!pos') >= 0 ??
            $cur."!cursor_pass"($!pos, 'after') !!
            nqp::bindattr_i($cur, $?CLASS, '$!pos', -3);
        nqp::bindattr_i($!shared, ParseShared, '$!highwater', $orig_highwater);
        nqp::bindattr($!shared, ParseShared, '@!highexpect', $orig_highexpect);
        $cur;
    }

    method ws() {
        # skip over any whitespace, fail if between two word chars
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        my $cur := self."!cursor_start_cur"();
        $!pos >= nqp::chars($target)
          ?? $cur."!cursor_pass"($!pos, 'ws')
          !! ($!pos < 1
              || !nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos)
              || !nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos-1)
             ) && $cur."!cursor_pass"(
                      nqp::findnotcclass(
                          nqp::const::CCLASS_WHITESPACE, $target, $!pos, nqp::chars($target)),
                      'ws');
        $cur;
    }
    
    method ww() {
        my $cur;
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        if $!pos > 0 && $!pos != nqp::chars($target)
                && nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos)
                && nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos-1) {
            $cur := self."!cursor_start_cur"();
            $cur."!cursor_pass"($!pos, "ww");
        }
        else {
            $cur := nqp::getattr($!shared, ParseShared, '$!fail_cursor');
        }
        $cur;
    }

    method wb() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos, "wb")
            if ($!pos == 0 && nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos))
               || ($!pos == nqp::chars($target)
                   && nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos-1))
               || nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos-1)
                  != nqp::iscclass(nqp::const::CCLASS_WORD, $target, $!pos);
        $cur;
    }

    method ident() {
        my $cur;
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        if $!pos < nqp::chars($target) &&
                (nqp::ord($target, $!pos) == 95
                 || nqp::iscclass(nqp::const::CCLASS_ALPHABETIC, $target, $!pos)) {
            $cur := self."!cursor_start_cur"();
            $cur."!cursor_pass"(
                nqp::findnotcclass(
                    nqp::const::CCLASS_WORD,
                    $target, $!pos, nqp::chars($target)));
        }
        else {
            $cur := nqp::getattr($!shared, ParseShared, '$!fail_cursor');
        }
        $cur;
    }

    method alpha() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'alpha')
          if $!pos < nqp::chars($target)
             && (nqp::iscclass(nqp::const::CCLASS_ALPHABETIC, $target, $!pos)
                 || nqp::ord($target, $!pos) == 95);
        $cur;
    }

    method alnum() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'alnum')
          if $!pos < nqp::chars($target)
             && (nqp::iscclass(nqp::const::CCLASS_ALPHANUMERIC, $target, $!pos)
                 || nqp::ord($target, $!pos) == 95);
        $cur;
    }

    method upper() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'upper')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_UPPERCASE, $target, $!pos);
        $cur;
    }

    method lower() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'lower')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_LOWERCASE, $target, $!pos);
        $cur;
    }

    method digit() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'digit')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_NUMERIC, $target, $!pos);
        $cur;
    }

    method xdigit() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'xdigit')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_HEXADECIMAL, $target, $!pos);
        $cur;
    }

    method space() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'space')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_WHITESPACE, $target, $!pos);
        $cur;
    }

    method blank() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'blank')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_BLANK, $target, $!pos);
        $cur;
    }

    method cntrl() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'cntrl')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_CONTROL, $target, $!pos);
        $cur;
    }

    method punct() {
        my $cur := self."!cursor_start_cur"();
        my str $target := nqp::getattr_s($!shared, ParseShared, '$!target');
        $cur."!cursor_pass"($!pos+1, 'punct')
          if $!pos < nqp::chars($target)
             && nqp::iscclass(nqp::const::CCLASS_PUNCTUATION, $target, $!pos);
        $cur;
    }

    method FAILGOAL($goal, $dba?) {
        unless $dba {
            $dba := nqp::getcodename(nqp::callercode());
        }
        nqp::die("Unable to parse expression in $dba; couldn't find final $goal");
    }
}


class NQPMatch is NQPCapture {
    has $!orig;
    has int $!from;
    has int $!to;
    has $!ast;
    has $!cursor;

    method from() { $!from }
    method orig() { $!orig }
    method to()   { $!to }
    method CURSOR() { $!cursor }
#?if parrot
    method Str() is parrot_vtable('get_string')  { nqp::substr($!orig, $!from, $!to-$!from) }
    method Int() is parrot_vtable('get_integer') { +self.Str() }
    method Num() is parrot_vtable('get_number')  { +self.Str() }
#?endif
#?if !parrot
    method Str() { nqp::substr($!orig, $!from, $!to-$!from) }
    method Int() { +self.Str() }
    method Num() { +self.Str() }
#?endif
    method Bool() { $!to >= $!from }
    method chars() { $!to >= $!from ?? $!to - $!from !! 0 }
    
    method !make($ast) { $!ast := $ast }
    method ast()       { $!ast }
    
    method dump($indent?) {
        unless nqp::defined($indent) {
            $indent := 0;
        }
        if self.Bool() {
            my @chunks;
            
            my sub dump_match(@chunks, $indent, $key, $value) {
                nqp::push(@chunks, nqp::x(' ', $indent));
                nqp::push(@chunks, '- ');
                nqp::push(@chunks, $key);
                nqp::push(@chunks, ': ');
                if nqp::can($value, 'Str') {
                    nqp::push(@chunks, $value.Str());
                }
                else {
                    nqp::push(@chunks, '<object>');
                }
                nqp::push(@chunks, "\n");
                if nqp::can($value, 'dump') {
                    nqp::push(@chunks, $value.dump($indent + 2));
                }
            }
            
            my sub dump_match_array(@chunks, $indent, $key, @matches) {
                nqp::push(@chunks, nqp::x(' ', $indent));
                nqp::push(@chunks, '- ');
                nqp::push(@chunks, $key);
                nqp::push(@chunks, ': ');
                nqp::push(@chunks, ~+@matches);
                nqp::push(@chunks, " matches\n");
                for @matches {
                    nqp::push(@chunks, $_.dump($indent + 2));
                }
            }
            
            my int $i := 0;
            for self.list() {
                if $_ {
                    nqp::islist($_)
                        ?? dump_match_array(@chunks, $indent, $i, $_)
                        !! dump_match(@chunks, $indent, $i, $_);
                }
                $i := $i + 1;
            }
            for self.hash() {
                if $_.value {
                    nqp::islist($_.value)
                        ?? dump_match_array(@chunks, $indent, $_.key, $_.value)
                        !! dump_match(@chunks, $indent, $_.key, $_.value);
                }
            }
            return join('', @chunks);
        }
        else {
            return nqp::x(' ', $indent) ~ "- NO MATCH\n";
        }
    }
    
    method !dump_str($key) {
        sub dump_array($key, $item) {
            my $str := '';
            if nqp::istype($item, NQPCapture) {
                $str := $str ~ $item."!dump_str"($key)
            }
            elsif nqp::islist($item) {
                $str := $str ~ "$key: list\n";
                my $n := 0;
                for $item { $str := $str ~ dump_array($key ~ "[$n]", $_); $n++ }
            }
            $str;
        }
        my $str := $key ~ ': ' ~ nqp::escape(self.Str) ~ ' @ ' ~ self.from ~ "\n";
        my $n := 0;
        for self.list { $str := $str ~ dump_array($key ~ '[' ~ $n ~ ']', $_); $n++ }
        for self.hash { $str := $str ~ dump_array($key ~ '<' ~ $_.key ~ '>', $_.value); }
        $str;
    }
}

class NQPCursor does NQPCursorRole {
    my @EMPTY_LIST := [];
    method MATCH() {
        my $match := nqp::getattr(self, NQPCursor, '$!match');
        unless nqp::istype($match, NQPMatch) || nqp::ishash($match) {
            my $list;
            my $hash := nqp::hash();
            $match := nqp::create(NQPMatch);
            nqp::bindattr(self, NQPCursor, '$!match', $match);
            nqp::bindattr($match, NQPMatch, '$!cursor', self);
            nqp::bindattr($match, NQPMatch, '$!orig', self.orig());
            nqp::bindattr_i($match, NQPMatch, '$!from', nqp::getattr_i(self, NQPCursor, '$!from'));
            nqp::bindattr_i($match, NQPMatch, '$!to', nqp::getattr_i(self, NQPCursor, '$!pos'));
            my %ch := self.CAPHASH;
            my $curcap;
            my str $key;
            my $iter := nqp::iterator(%ch);
            while $iter {
                $curcap := nqp::shift($iter);
                $key := nqp::iterkey_s($curcap);
                if nqp::iscclass(nqp::const::CCLASS_NUMERIC, $key, 0) {
                    $list := nqp::list() unless nqp::isconcrete($list);
                    nqp::bindpos($list, $key, nqp::iterval($curcap));
                }
                elsif $key && nqp::ordat($key, 0) == 36 && ($key eq '$!from' || $key eq '$!to') {
                    nqp::bindattr_i($match, NQPMatch, $key, nqp::iterval($curcap).from);
                }
                else {
                    nqp::bindkey($hash, $key, nqp::iterval($curcap));
                }
            }
            nqp::bindattr($match, NQPCapture, '@!array', nqp::isconcrete($list) ?? $list !! @EMPTY_LIST);
            nqp::bindattr($match, NQPCapture, '%!hash', $hash);
        }
        $match
    }

    method Bool() {
        !nqp::isnull(nqp::getattr(self, $?CLASS, '$!match'))
          && nqp::istrue(nqp::getattr(self, $?CLASS, '$!match'));
    }

    method parse($target, :$rule = 'TOP', :$actions, *%options) {
        my $*ACTIONS := $actions;
        my $cur := self.'!cursor_init'($target, |%options);
        nqp::bindattr(nqp::getattr($cur, NQPCursor, '$!shared'), ParseShared, '$!ACTIONS', $actions);
        nqp::isinvokable($rule) ??
            $rule($cur).MATCH() !!
            nqp::findmethod($cur, $rule)($cur).MATCH()
    }

    method !INTERPOLATE($var, $s = 0) {
        if nqp::islist($var) {
            my int $maxlen := -1;
            my $cur := self.'!cursor_start_cur'();
            my int $pos := nqp::getattr_i($cur, $?CLASS, '$!from');
            my str $tgt := $cur.target;
            my int $eos := nqp::chars($tgt);
            for $var {
                if nqp::isinvokable($_) {
                    my $res := $_(self);
                    if $res {
                        my int $adv := nqp::getattr_i($res, $?CLASS, '$!pos');
                        $adv := $adv - $pos;
                        $maxlen := $adv if $adv > $maxlen;
                    }
                }
                else {
                    my int $len := nqp::chars($_);
                    $maxlen := $len if $len > $maxlen && $pos + $len <= $eos
                        && nqp::substr($tgt, $pos, $len) eq $_;
                }
                last if $s && $maxlen > -1;
            }
            $cur.'!cursor_pass'($pos + $maxlen, '') if $maxlen >= 0;
            return $cur;
        }
        else {
            return $var(self) if nqp::isinvokable($var);
            my $cur := self.'!cursor_start_cur'();
            my int $pos := nqp::getattr_i($cur, $?CLASS, '$!from');
            my str $tgt := $cur.target;
            my int $len := nqp::chars($var);
            my int $adv := $pos + $len;
            return $cur if $adv > nqp::chars($tgt)
                || nqp::substr($tgt, $pos, $len) ne $var;
            $cur.'!cursor_pass'($adv, '');
            return $cur;
        }
    }

    method !INTERPOLATE_REGEX($var) {
        unless nqp::isinvokable($var) {
            my $rxcompiler := nqp::getcomp('QRegex::P6Regex');
            if nqp::islist($var) {
                my $res := [];
                for $var {
                    my $elem := $_;
                    $elem := $rxcompiler.compile($elem) unless nqp::isinvokable($elem);
                    nqp::push($res, $elem);
                }
                $var := $res;
            }
            else {
                $var := $rxcompiler.compile($var);
            }
        }
        return self.'!INTERPOLATE'($var);
    }
}

class NQPRegexMethod {
    has $!code;
    method new($code) {
        self.bless(:code($code));
    }
    multi method ACCEPTS(NQPRegexMethod:D $self: $target) {
        NQPCursor.parse($target, :rule(self))
    }
    method name() {
        nqp::getcodename($!code)
    }
    method Str() {
        self.name()
    }
}
nqp::setinvokespec(NQPRegexMethod, NQPRegexMethod, '$!code', nqp::null);

class NQPRegex is NQPRegexMethod {
    multi method ACCEPTS(NQPRegex:D $self: $target) {
        NQPCursor.parse($target, :rule(self), :c(0))
    }
}
nqp::setinvokespec(NQPRegex, NQPRegexMethod, '$!code', nqp::null);
