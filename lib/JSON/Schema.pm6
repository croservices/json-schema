use v6;

class X::JSON::Schema::BadSchema is Exception {
    has $.path;
    has $.reason;

    method message() {
        "Schema invalid at $!path: $!reason"
    }
}

class X::JSON::Schema::Failed is Exception {
    has $.path;
    has $.reason;
    method message() {
        "Validation failed for $!path: $!reason"
    }
}

class JSON::Schema {
    # Role that describes a single check for a given path.
    # `chech` method is overloaded, with possible usage of additional per-class
    # attributes
    my role Check {
        has $.path;
        method check($value --> Nil) { ... }
    }

    my class AllCheck does Check {
        has $.native = True;
        has @.checks;
        method check($value --> Nil) {
            for @!checks.kv -> $i, $c {
                $c.check($value);
                CATCH {
                    when X::JSON::Schema::Failed {
                        my $path = $!native ?? .path !! "{.path}/{$i + 1}";
                        die X::JSON::Schema::Failed.new(:$path, reason => .reason);
                    }
                }
            }
        }
    }

    my class OrCheck does Check {
        has @.checks;
        method check($value --> Nil) {
            for @!checks.kv -> $i, $c {
                $c.check($value);
                return;
                CATCH {
                    when X::JSON::Schema::Failed {}
                }
            }
            die X::JSON::Schema::Failed.new(:$!path, :reason('Does not satisfy any check'));
        }
    }

    my role TypeCheck does Check {
        method check($value --> Nil) {
            unless $value.defined && $value ~~ $.type {
                die X::JSON::Schema::Failed.new(path => $.path, reason => $.reason);
            }
        }
    }

    my class StringCheck does TypeCheck {
        has $.reason = 'Not a string';
        has $.type = Str;
    }

    my class IntegerCheck does TypeCheck {
        has $.reason = 'Not an integer';
        has $.type = Int;
    }

    has Check $!check;

    submethod BUILD(:%schema! --> Nil) {
        $!check = check-for('root', %schema);
    }

    sub check-for-type($path, $_) {
        when 'string' {
            StringCheck.new(:$path);
        }
        when 'integer' {
            IntegerCheck.new(:$path);
        }
        default {
            die X::JSON::Schema::BadSchema.new(:$path, :reason("Unrecognized type '$_'"));
        }
    }

    sub check-for($path, %schema) {
        my @checks;

        with %schema<type> {
            when Str {
                push @checks, check-for-type($path, $_);
            }
            when List {
                unless (all $_) ~~ Str {
                    die X::JSON::Schema::BadSchema.new:
                      :$path, :reason("Non-string elements are present in type constraint");
                }
                unless $_.unique ~~ $_ {
                    die X::JSON::Schema::BadSchema.new:
                      :$path, :reason("Non-unique elements are present in type constraint");
                }

                my @type-checks = $_.map({ check-for-type($path, $_) });
                push @checks, OrCheck.new(:path("$path/anyOf"),
                                          checks => @type-checks);
            }
            default {
                die X::JSON::Schema::BadSchema.new(:$path, :reason("Type property must be a string"));
            }
        }

        @checks == 1 ?? @checks[0] !! AllCheck.new(:@checks);
    }

    method validate($value --> True) {
        $!check.check($value);
        CATCH {
            when X::JSON::Schema::Failed {
                fail $_;
            }
        }
    }
}
