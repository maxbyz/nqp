# vi: filetype=perl6:
sub comment($comment) {
    say("# $comment");
}
sub constant($name, $value) {
    say("$name = $value");
}

sub stage_path($stage) {
    '$(JS_STAGE' ~ $stage ~ ')/';
}

sub make_parents($path) {
    my $parts := nqp::split("/",$path);
    nqp::pop($parts);
    '$(MKPATH) ' ~ nqp::join('/',$parts);
}

sub rule($target, $source, *@actions) {
    my $rule := "$target: $source\n";
    for @actions -> $action {
        if $rule ne '' {
            $rule := $rule ~ "\t$action\n";
        }
    }
    say($rule);
    $target;
}

sub nqp($prefix, $file, $stage, :$deps=[]) {
    my $source := $prefix ~ '/' ~ $file ~ '.nqp';
    my $path := stage_path($stage);
    my $pbc := $path ~ $file ~ '.pbc';
    my $pir := $path ~ $file ~ '.pir';

    my $installed_pbc := 'gen/parrot/' ~ $file ~ '.pbc';

    nqp::unshift($deps, $source);

    rule($pbc, nqp::join(' ', $deps),
        make_parents($pbc),
        "\$(JS_NQP) --target=pir --output=$pir --encoding=utf8 $source",
        "\$(JS_PARROT) -o $pbc $pir",
        # HACK - workaround for not being able to supply multiple directories to --module-path
        make_parents($installed_pbc),
        "\$(CP) $pbc $installed_pbc"
    );
}

sub deps($target, *@deps) {
    say("$target : {nqp::join(' ',@deps)}");
}

sub combine(:$sources, :$stage, :$file, :$gen-version = 0) {

    my $target := stage_path($stage) ~ $file;
    my $version := stage_path($stage) ~ 'nqp-config.nqp';

    rule($target, $sources,
        make_parents($target),
        $gen-version ?? "\$(PERL) tools/build/gen-version.pl > $version" !! '',
        "\$(PERL) tools/build/gen-cat.pl js $sources {$gen-version ?? $version !! ''} > $target"
    ); 
}

sub cross-compile(:$stage, :$source, :$target, :$setting, :$no-regex-lib, :$deps = []) {
    my $path := stage_path($stage);
    my $pir := $path ~ $target ~ '.pir';
    my $pbc := $path ~ $target ~ '.pbc';
    # todo dependency on compiler
    
    nqp::unshift($deps, $source);
    nqp::unshift($deps, '$(JS_STAGE1_COMPILER)');

    rule($pbc, nqp::join(' ', $deps), 
        make_parents($pbc),
	"\$(JS_NQP) src/vm/js/bin/cross-compile.nqp $source $path $target $setting $no-regex-lib",
        "\$(JS_PARROT)  -o $pbc $pir");


}


comment("This is the JS Makefile - autogenerated by gen-makefile.nqp");

constant('JS_BUILD_DIR','gen/js');
constant('JS_STAGE1','$(JS_BUILD_DIR)/stage1');
constant('JS_STAGE2','$(JS_BUILD_DIR)/stage2');
constant('JS_NQP','$(P_RUNNER)$(BAT)');
constant('JS_PARROT','$(PARROT_BIN_DIR)/parrot$(EXE) $(PARROT_ARGS)');

say('js-runner-default: js-all');

my $stage1-qast-compiler-pbc := nqp('src/vm/js','QAST/Compiler',1);
my $stage1-hll-backend-pbc := nqp('src/vm/js','HLL/Backend',1,:deps([$stage1-qast-compiler-pbc]));

constant('JS_STAGE1_COMPILER',"$stage1-qast-compiler-pbc $stage1-hll-backend-pbc");


my $nqp-mo-combined := combine(:stage(2), :sources('$(NQP_MO_SOURCES)'), :file('$(NQP_MO_COMBINED)'));
my $nqp-mo-pbc := cross-compile(:stage(2), :source($nqp-mo-combined), :target('nqpmo'), :setting('NULL'), :no-regex-lib(1));

my $nqpcore-combined := combine(:stage(2), :sources('$(CORE_SETTING_SOURCES)'), :file('$(CORE_SETTING_COMBINED).nqp'));
my $nqpcore-pbc := cross-compile(:stage(2), :source($nqpcore-combined), :target('NQPCORE.setting'), :setting('NULL'), :no-regex-lib(1), :deps([$nqp-mo-pbc]));

my $QASTNode-combined := combine(:stage(2), :sources('$(QASTNODE_SOURCES)'), :file('$(QASTNODE_COMBINED)'));
my $QASTNode-pbc := cross-compile(:stage(2), :source($QASTNode-combined), :target('QASTNode'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-pbc]));

my $QRegex-combined := combine(:stage(2), :sources('$(QREGEX_SOURCES)'), :file('$(QREGEX_COMBINED)'));
my $QRegex-pbc := cross-compile(:stage(2), :source($QRegex-combined), :target('QRegex'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-pbc, $QASTNode-pbc]));

my $QAST-Compiler-pbc := cross-compile(:stage(2), :source('src/vm/js/QAST/Compiler.nqp'), :target('QAST/Compiler'), :setting('NQPCORE'), :no-regex-lib(0), :deps([$nqpcore-pbc, $QASTNode-pbc]));

my $NQPHLL-combined := combine(:stage(2), :sources('src/vm/js/HLL/Backend.nqp $(COMMON_HLL_SOURCES)'), :file('$(HLL_COMBINED)')); 
my $NQPHLL-pbc := cross-compile(:stage(2), :source($NQPHLL-combined), :target('NQPHLL'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-pbc, $QAST-Compiler-pbc]));

my $QAST-pbc := cross-compile(:stage(2), :source('src/vm/js/QAST.nqp'), :target('QAST'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-pbc, $QASTNode-pbc]));

my $NQPP6QRegex-combined := combine(:stage(2), :sources('$(P6QREGEX_SOURCES)'), :file('$(P6QREGEX_COMBINED)')); 
my $NQPP6QRegex-pbc := cross-compile(:stage(2), :source($NQPP6QRegex-combined), :target('NQPP6QRegex'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-pbc, $QRegex-pbc, $NQPHLL-pbc, $QAST-pbc]));


my $NQP-combined := combine(:stage(2), :sources('$(COMMON_NQP_SOURCES)'), :file('$(NQP_COMBINED)'), :gen-version(1));

say("nqp-js.js: $nqpcore-pbc $QASTNode-pbc $QRegex-pbc $NQPP6QRegex-pbc $NQP-combined
	./nqp-js-compile gen/js/stage2/NQP.nqp > nqp-js.js
");

deps('js-stage1-compiler', '$(JS_STAGE1_COMPILER)');
#constant('JS_ALL'," $nqpcore-pbc $QASTNode-pbc $QRegex-pbc $NQPP6QRegex-pbc $NQP-combined");

deps("js-all", 'p-all', 'js-stage1-compiler', 'node_modules/installed');
#deps("js-all", 'p-all', 'js-stage1-compiler', '$(JS_ALL)', 'node_modules/installed');

# we don't have a proper runner yet but the Makefile structure requires that
deps('js-runner-default', 'js-all');

say('js-test: js-all
	src/vm/js/bin/run_tests');

#	npm install src/vm/js/nqp-runtime-core src/vm/js/nqp-runtime-node src/vm/js/nqp-runtime gen/js/stage2/NQPCORE.setting gen/js/stage2/QRegex gen/js/stage2/nqpmo gen/js/stage2/QASTNode gen/js/stage2/QAST gen/js/stage2/NQPP6QRegex gen/js/stage2/NQPHLL

say('node_modules/installed: src/vm/js/nqp-runtime/runtime.js
	npm install src/vm/js/nqp-runtime
	touch node_modules/installed');

say("\n\njs-clean:
	\$(RM_RF) gen/js/stage1 gen/js/stage2 gen/parrot/QAST gen/parrot/HLL
");
say("js-lint:
	gjslint --strict --nojsdoc src/vm/js/nqp-runtime/*.js");
