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

    my class NullCheck does TypeCheck {
        method check($value --> Nil) {
            unless $value ~~ Nil {
                die X::JSON::Schema::Failed.new(path => $.path, reason => 'Not a null');
            }
        }
    }

    my class BooleanCheck does TypeCheck {
        has $.reason = 'Not a boolean';
        has $.type = Bool;
    }

    my class ObjectCheck does TypeCheck {
        has $.reason = 'Not an object';
        has $.type = Associative;
    }

    my class ArrayCheck does TypeCheck {
        has $.reason = 'Not an array';
        has $.type = Positional;
    }

    my class NumberCheck does TypeCheck {
        has $.reason = 'Not a number';
        has $.type = Rat;
    }

    my class StringCheck does TypeCheck {
        has $.reason = 'Not a string';
        has $.type = Str;
    }

    my class IntegerCheck does TypeCheck {
        has $.reason = 'Not an integer';
        has $.type = Int;
    }

    my class EnumCheck does Check {
        has $.enum;
        method check($value --> Nil) {
            return if $value ~~ Nil && Nil (elem) $!enum;
            unless $value.defined && $value (elem) $!enum {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Value '$value' is outside of enumeration set by enum property");
            }
        }
    }

    my class ConstCheck does Check {
        has $.const;
        method check($value --> Nil) {
            unless $value eqv $!const {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Value '$value' does not match with constant $!const");   
            }
        }
    }

    my class MultipleOfCheck does Check {
        has UInt $.multi;
        method check($value --> Nil) {
            if $value ~~ Real {
                unless $value %% $!multi {
                    die X::JSON::Schema::Failed.new:
                        :$!path, :reason("Number is not multiple of $!multi");
                }
            }
        }
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
        when 'null' {
            NullCheck.new(:$path);
        }
        when 'boolean' {
            BooleanCheck.new(:$path);
        }
        when 'object' {
            ObjectCheck.new(:$path);
        }
        when 'array' {
            ArrayCheck.new(:$path);
        }
        when 'number' {
            NumberCheck.new(:$path);
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

        with %schema<enum> {
            unless $_ ~~ Positional {
                die X::JSON::Schema::BadSchema.new:
                :$path, :reason("enum property value must be an array");
            }
            push @checks, EnumCheck.new(:$path, enum => $_);
        }

        with %schema<const> {
            push @checks, ConstCheck.new(:$path, const => $_);
        }

        with %schema<multipleOf> {
            when * ~~ Int && * > 0 {
                push @checks, MultipleOfCheck.new(:$path, multi => $_);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The multipleOf property must be a non-negative integer");
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
