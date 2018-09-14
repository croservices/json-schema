use v6;
use JSON::ECMA262Regex;

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
            unless $value.defined && so $!enum.map(* eqv $value).any {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Value '{$value.perl}' is outside of enumeration set by enum property");
            }
        }
    }

    my class ConstCheck does Check {
        has $.const;
        method check($value --> Nil) {
            unless $value eqv $!const {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Value '{$value.perl}' does not match with constant $!const");
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

    my role CmpCheck does Check {
        has Int $.border-value;

        method check($value --> Nil) {
            if $value ~~ Real {
                unless self.compare($value, $!border-value) {
                    die X::JSON::Schema::Failed.new:
                        path => $.path, :reason("$value is {self.reason} $!border-value");
                }
            }
        }
    }

    my class MinCheck does CmpCheck {
        method reason { 'less than' }
        method compare($value-to-compare, $border-value) { $value-to-compare >= $border-value }
    }

    my class MinExCheck does CmpCheck {
        method reason { 'less or equal than' }
        method compare($value-to-compare, $border-value) { $value-to-compare > $border-value }
    }

    my class MaxCheck does CmpCheck {
        method reason { 'more than' }
        method compare($value-to-compare, $border-value) { $value-to-compare <= $border-value }
    }

    my class MaxExCheck does CmpCheck {
        method reason { 'more or equal than' }
        method compare($value-to-compare, $border-value) { $value-to-compare < $border-value }
    }

    my class MinLengthCheck does Check {
        has Int $.value;
        method check($value --> Nil) {
            if $value ~~ Str && $value.defined && $value.codes < $!value {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("String is less than $!value codepoints");
            }
        }
    }

    my class MaxLengthCheck does Check {
        has Int $.value;
        method check($value --> Nil) {
            if $value ~~ Str && $value.defined && $value.codes > $!value {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("String is more than $!value codepoints");
            }
        }
    }

    my class PatternCheck does Check {
        has Str $.pattern;
        has Regex $!rx;
        submethod TWEAK() {
            use MONKEY-SEE-NO-EVAL;
            $!rx = EVAL 'rx:P5/' ~ $!pattern ~ '/';
        }
        method check($value --> Nil) {
            if $value ~~ Str && $value !~~ $!rx {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("String does not match /$!pattern/");
            }
        }
    }

    my class MinItemsCheck does Check {
        has Int $.value;
        method check($value --> Nil) {
            if $value ~~ Positional && $value.elems < $!value {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Array has less than $!value elements");
            }
        }
    }

    my class MaxItemsCheck does Check {
        has Int $.value;
        method check($value --> Nil) {
            if $value ~~ Positional && $value.elems > $!value {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Array has less than $!value elements");
            }
        }
    }

    my class UniqueItemsCheck does Check {
        method check($value --> Nil) {
            if $value ~~ Positional && $value.elems != $value.unique(with => &[eqv]).elems {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Array has duplicated values");
            }
        }
    }

    my class ItemsByObjectCheck does Check {
        has Check $.check;

        method check($value --> Nil) {
            if $value ~~ Positional {
                for @$value -> $item {
                    $!check.check($item);
                }
            }
        }
    }

    my class ItemsByArraysCheck does Check {
        has Check @.checks;

        method check($value --> Nil) {
            if $value ~~ Positional {
                for @$value Z @!checks -> ($item, $check) {
                    $check.check($item);
                }
            }
        }
    }

    my class AdditionalItemsCheck does Check {
        has Check $.check;
        has Int $.size;

        method check($value --> Nil) {
            if $value ~~ Positional && $value.elems > $!size {
                for @$value[$!size..*] -> $item {
                    $!check.check($item);
                }
            }
        }
    }

    my class ContainsCheck does Check {
        has Check $.check;

        method check($value --> Nil) {
            if $value ~~ Positional {
                for @$value -> $item {
                    CATCH {
                        when X::JSON::Schema::Failed {}
                    }
                    $!check.check($item);
                    return;
                }
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Array does not contain any element that is accepted by `contains` check");
            }
        }
    }

    my class MinPropertiesCheck does Check {
        has Int $.min;
        method check($value --> Nil) {
            if $value ~~ Associative && $value.values < $!min {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Object has less than $!min properties");
            }
        }
    }

    my class MaxPropertiesCheck does Check {
        has Int $.max;
        method check($value --> Nil) {
            if $value ~~ Associative && $value.values > $!max {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Object has more than $!max properties");
            }
        }
    }

    my class RequiredCheck does Check {
        has Str @.prop;
        method check($value --> Nil) {
            if $value ~~ Associative && not [&&] $value{@!prop}.map(*.defined) {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Object does not have required property");
            }
        }
    }

    my class PropertiesCheck does Check {
        has Check %.props;
        has $.add;
        method check($value --> Nil) {
            if $value ~~ Associative && $value.defined {
                if $!add === True {
                    for (%!props.keys (&) $value.keys).keys -> $key {
                        %!props{$key}.check($value{$key});
                    }
                } elsif $!add === False {
                    if (set $value.keys) ⊈ (set %!props.keys) {
                        die X::JSON::Schema::Failed.new:
                            path => $!path ~ '/properties',
                            :reason("Object has properties that are not covered by properties property: $((set $value.keys) (-) (set %!props.keys)).keys.join(', ')");
                    } else {
                        $value.keys.map({ %!props{$_}.check($value{$_}) });
                    }
                } else {
                    for (%!props.keys (&) $value.keys).keys -> $key {
                        %!props{$key}.check($value{$key});
                    }
                    if $!add.elems != 0 {
                        for ($value.keys (-) %!props.keys).keys -> $key {
                            $!add.check($value{$key});
                        }
                    }
                }
            }
        }
    }

    my class PatternProperties does Check {
        has @.regex-checks;

        method check($value --> Nil) {
            return if $value !~~ Associative || !$value.defined;
            for $value.kv -> $prop, $val {
                for @!regex-checks {
                    my $regex = .key;
                    my $inner-check = .value;
                    try $regex.check($prop);
                    next if $! ~~ X::JSON::Schema::Failed;
                    # If value survived regex check, check it
                    $inner-check.check($val);
                }
            }
        }
    }

    my class AdditionalProperties does Check {
        has @.inner-const-checks;
        has @.inner-regex-checks;
        has Check $.check;

        method check($value --> Nil) {
            return if $value !~~ Associative || !$value.defined;
            for $value.kv -> $prop, $val {
                my $already-checked = False;
                for @!inner-const-checks {
                    # Skip if the property is already checked with `properties`
                    try .check($prop);
                    if $! !~~ X::JSON::Schema::Failed {
                        $already-checked = True;
                        last;
                    }
                }
                next if $already-checked;
                for @!inner-regex-checks {
                    # Skip if `patternProperties` check was successful
                    try .check($prop);
                    if $! !~~ X::JSON::Schema::Failed {
                        $already-checked = True;
                        last;
                    }
                }
                next if $already-checked;
                $!check.check($val);
            }
        }
    }

    my class DependencyCheck does Check {
        has Str $.prop;
        has Check $.check;
        method check($value --> Nil) {
            $!check.check($value) if $value ~~ Associative && $value{$!prop};
        }
    }

    my class PropertyNamesCheck does Check {
        has Check $.check;

        method check($value --> Nil) {
            if $value ~~ Associative {
                $!check.check($_) for $value.keys;
            }
        }
    }

    my class ConditionalCheck does Check {
        has Check $.if;
        has Check $.then;
        has Check $.else;

        method check($value --> Nil) {
            try $!if.check($value);
            if !$!.defined {
                $!then.check($value);
            }
            else {
                $!else.check($value);
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
            die X::JSON::Schema::BadSchema.new(:$path, :reason("Unrecognized type '{$_.^name}'"));
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
            when $_ ~~ Int && $_ > 0 {
                push @checks, MultipleOfCheck.new(:$path, multi => $_);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The multipleOf property must be a non-negative integer");
            }
        }

        my %num-keys = minimum => MinCheck, minimumExclusive => MinExCheck,
                       maximum => MaxCheck, maximumExclusive => MaxExCheck;
        for %num-keys.kv -> $k, $v {
            with %schema{$k} {
                unless $_ ~~ Real {
                    die X::JSON::Schema::BadSchema.new:
                        :$path, :reason("The $k property must be a number");
                }
                push @checks, $v.new(:$path, border-value => $_);
            }
        }

        my %str-keys = minLength => MinLengthCheck, maxLength => MaxLengthCheck;
        for %str-keys.kv -> $prop, $check {
            with %schema{$prop} {
                when UInt {
                    push @checks, $check.new(:$path, value => $_);
                }
                default {
                    die X::JSON::Schema::BadSchema.new:
                        :$path, :reason("The $prop property must be a non-negative integer");
                }
            }
        }

        with %schema<pattern> {
            when Str {
                if ECMA262Regex.parse($_) {
                    push @checks, PatternCheck.new(:$path, :pattern($_));
                }
                else {
                    die X::JSON::Schema::BadSchema.new:
                        :$path, :reason("The pattern property must be an ECMA 262 regex");
                }
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The pattern property must be a string");
            }
        }

        with %schema<items> {
            when Associative {
                push @checks, ItemsByObjectCheck.new(:$path, check => check-for($path, $_));
            }
            when Positional {
                unless ($_.all) ~~ Hash {
                    die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The item property array must contain only objects");
                }

                my @items-checks = $_.map({ check-for($path, $_) });
                push @checks, ItemsByArraysCheck.new(:$path, checks => @items-checks);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The item property must be a JSON Schema or array of JSON Schema objects");
            }
        }

        with %schema<additionalItems> {
            when Associative {
                if %schema<items> ~~ Positional {
                    my $check = check-for($path, $_);
                    push @checks, AdditionalItemsCheck.new(:$path, :$check, size => %schema<items>.elems);
                }
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The additionalItems property must be a JSON Schema object");
            }
        }

        my %array-keys = minItems => MinItemsCheck, maxItems => MaxItemsCheck;
        for %array-keys.kv -> $prop, $check {
            with %schema{$prop} {
                when UInt {
                    push @checks, $check.new(:$path, value => $_);
                }
                default {
                    die X::JSON::Schema::BadSchema.new:
                        :$path, :reason("The $prop property must be a non-negative integer");
                }
            }

        }
        with %schema<uniqueItems> {
            when $_ === True {
                push @checks, UniqueItemsCheck.new(:$path);
            }
            when  $_ === False {}
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The uniqueItems property must be a boolean");
            }
        }

        with %schema<contains> {
            when Associative {
                my $check = check-for($path, $_);
                push @checks, ContainsCheck.new(:$path, :$check);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The contains property must be a JSON Schema object");
            }
        }

        with %schema<minProperties> {
            when UInt {
                push @checks, MinPropertiesCheck.new(:$path, :min($_));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The minProperties property must be a non-negative integer");
            }
        }

        with %schema<maxProperties> {
            when UInt {
                push @checks, MaxPropertiesCheck.new(:$path, :max($_));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The maxProperties property must be a non-negative integer");
            }
        }

        with %schema<required> {
            when Positional {
                if ([&&] .map(* ~~ Str)) && .elems == .unique.elems {
                    push @checks, RequiredCheck.new(:$path, prop => @$_);
                } else {
                    proceed;
                }
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The required property must be a Positional of unique Str");
            }
        }

        with %schema<properties> {
            when Associative {
                unless .values.map(* ~~ Associative).all {
                    die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The properties property inner values must be an object");
                }
                my %props = .map({ .key => check-for($path ~ "/properties/{.key}", %(.value)) });
                push @checks, PropertiesCheck.new(:$path, :%props, add => {});
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The properties property must be an object");
            }
        }

        with %schema<patternProperties> {
            when Associative {
                my @regex-checks;
                for .kv -> $pattern, $schema {
                    # A number of check -> inner check pairs
                    @regex-checks.push: PatternCheck.new(:$pattern) => check-for($path, $schema);
                }
                push @checks, PatternProperties.new(:$path, :@regex-checks);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The patternProperties property must be an object");
            }
        }

        with %schema<additionalProperties> {
            when Associative {
                my @inner-const-checks;
                my @inner-regex-checks;
                with %schema<properties> {
                    for .keys -> $name {
                        push @inner-const-checks, ConstCheck.new(:$path, const => $name);
                    }
                }
                with %schema<patternProperties> {
                    for .keys -> $pattern {
                        push @inner-regex-checks, PatternCheck.new(:$pattern);
                    }
                }
                push @checks, AdditionalProperties.new(:$path, check => check-for($path, $_),
                                                       :@inner-regex-checks, :@inner-const-checks);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The additionalProperties property must be an object");
            }
        }

        with %schema<dependencies> {
            when Associative {
                for .kv -> $prop, $_ {
                    if $_ !~~ Associative|Positional {
                        die X::JSON::Schema::BadSchema.new:
                            :$path, :reason("The dependencies properties values must be an object or a list");
                    }
                    if $_ ~~ Positional && not .map(* ~~ Str).all {
                        die X::JSON::Schema::BadSchema.new:
                            :$path, :reason("The dependencies property array value must contain only string objects");
                    }

                    my $check = $_ ~~ Positional ??
                        RequiredCheck.new(:$path, prop => @$_) !!
                        check-for($path, $_);
                    push @checks, DependencyCheck.new(:$path, :$prop, :$check);
                }
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The dependencies property must be an object");
            }
        }

        my $then = %schema<then>;
        if $then.defined && $then !~~ Associative {
            die X::JSON::Schema::BadSchema.new:
            :$path, :reason("The then property must be an object");
        }
        my $else = %schema<else>;
        if $else.defined && $else !~~ Associative {
            die X::JSON::Schema::BadSchema.new:
            :$path, :reason("The else property must be an object");
        }

        with %schema<if> {
            unless $_ ~~ Associative {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The if property must be an object");
            }
            if $then.defined || $else.defined {
                push @checks, ConditionalCheck.new(if => check-for($path, $_),
                                                   then => $then.defined ?? check-for($path, $then) !! Nil,
                                                   else => $else.defined ?? check-for($path, $else) !! Nil);
            }
        }

        with %schema<propertyNames> {
            when Associative {
                my $check = check-for($path, $_);
                push @checks, PropertyNamesCheck.new(:$path, :$check);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The propertyNames property must be an object");
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
