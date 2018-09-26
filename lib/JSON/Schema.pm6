use v6;
use Cro::Uri;
use DateTime::Parse;
use JSON::ECMA262Regex;
use JSON::Pointer;
use JSON::Pointer::Relative;

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
    my %DEFAULT-FORMAT =
        date-time => { CATCH {default {False}}; DateTime::Parse.new($_, :rule('rfc3339-date')) },
        date => { CATCH {default {False}}; DateTime::Parse.new($_, :rule('date5')) },
        time => { CATCH {default {False}}; DateTime::Parse.new($_, :rule('time2')) },
        email => { True },
        idn-email => { True },
        hostname => { True },
        idn-hostname => { True },
        ipv4 => { CATCH {default {False}}; Cro::Uri::GenericParser.parse($_, :rule('IPv4address')) },
        ipv6 => { CATCH {default {False}}; Cro::Uri::GenericParser.parse($_, :rule('IPv6address')) },
        uri => { CATCH {default {False}}; Cro::Uri.parse($_) },
        uri-reference => { CATCH {default {False}}; Cro::Uri::GenericParser.parse($_, :rule<relative-ref>) },
        iri => { True },
        iri-reference => { True },
        uri-template => { CATCH {default {False}}; Cro::Uri::URI-Template.parse($_) },
        json-pointer => { CATCH {default {False}}; JSONPointer.parse($_) },
        relative-json-pointer => { CATCH {default {False}}; JSONPointerRelative.parse($_) },
        regex => { CATCH {default {False}}; ECMA262Regex.parse($_) };

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

    my class OneCheck does Check {
        has @.checks;
        method check($value --> Nil) {
            my $check = False;
            my $failed = False;
            for @!checks.kv -> $i, $c {
                $c.check($value);
                if $check {
                    $failed = True;
                } else {
                    $check = True;
                }
                CATCH {
                    when X::JSON::Schema::Failed {}
                }
            }
            if $failed {
                die X::JSON::Schema::Failed.new:
                :$!path, :reason('Value passed more than a single check');
            }
            unless $check {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason('Value does not passed a single check') unless $check;
            }
        }
    }

    my class NotCheck does Check {
        has Check $.check;
        method check($value --> Nil) {
            $!check.check($value);
            CATCH {
                when X::JSON::Schema::Failed {
                    return;
                }
            }
            fail X::JSON::Schema::Failed.new:
                :$!path, :reason('Value passed check check');
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
        has $.type = Rat|Num;
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
            if $value ~~ Associative and @!prop.grep({ not $value{$_}.defined }) -> @missing {
                die X::JSON::Schema::Failed.new:
                    :$!path,
                    :reason("Missing required properties: @missing.map({ qq/'$_'/ }).join(', ')");
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

    my class FormatCheck does Check {
        has $.checker;
        has $.format-name;
        method check($value --> Nil) {
            unless $value ~~ $!checker {
                die X::JSON::Schema::Failed.new:
                    :$!path, :reason("Value $value does not match against $!format-name format");
            }
        }
    }

    has Check $!check;

    submethod BUILD(:%schema!, :%formats = %DEFAULT-FORMAT, :%add-formats = {} --> Nil) {
        $!check = check-for('root', %schema, :%formats, :%add-formats);
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

    sub check-for($path, %schema, :%formats, :%add-formats) {
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
                push @checks, ItemsByObjectCheck.new(:$path, check => check-for($path ~ '/items', $_, :%formats, :%add-formats));
            }
            when Positional {
                unless ($_.all) ~~ Hash {
                    die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The item property array must contain only objects");
                }

                my @items-checks = $_.map({ check-for($path ~ '/items', $_, :%formats, :%add-formats) });
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
                    my $check = check-for($path ~ '/additionalProperties', $_, :%formats, :%add-formats);
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
                my $check = check-for($path ~ '/contains', $_, :%formats, :%add-formats);
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
                my %props = .map({ .key => check-for($path ~ "/properties/{.key}", %(.value), :%formats, :%add-formats) });
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
                    @regex-checks.push: PatternCheck.new(:$pattern) => check-for($path ~ '/patternProperties', $schema, :%formats, :%add-formats);
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
                push @checks, AdditionalProperties.new(:$path, check => check-for($path ~ '/additionalProperties', $_, :%formats, :%add-formats),
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
                        check-for($path ~ '/dependencies', $_, :%formats, :%add-formats);
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
                push @checks, ConditionalCheck.new(if => check-for($path ~ '/if', $_, :%formats, :%add-formats),
                                                   then => $then.defined ?? check-for($path ~ '/then', $then, :%formats, :%add-formats) !! Nil,
                                                   else => $else.defined ?? check-for($path ~ '/else', $else, :%formats, :%add-formats) !! Nil);
            }
        }

        with %schema<propertyNames> {
            when Associative {
                my $check = check-for($path ~ '/propertyNames', $_, :%formats, :%add-formats);
                push @checks, PropertyNamesCheck.new(:$path, :$check);
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The propertyNames property must be an object");
            }
        }

        with %schema<allOf> {
            when Positional {
                push @checks, AllCheck.new(:path("$path/allOf"),
                                           native => False,
                                           checks => .map({ check-for($path ~ '/allOf', $_, :%formats, :%add-formats) }));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The allOf property must be an array");
            }
        }

        with %schema<anyOf> {
            when Positional {
                push @checks, OrCheck.new(:path("$path/anyOf"),
                                          checks => .map({ check-for($path ~ '/anyOf', $_, :%formats, :%add-formats) }));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The anyOf property must be an array");
            }
        }

        with %schema<oneOf> {
            when Positional {
                push @checks, OneCheck.new(:path("$path/oneOf"),
                                           checks => .map({ check-for($path ~ '/oneOf', $_, :%formats, :%add-formats) }));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The oneOf property must be an array");
            }
        }

        with %schema<not> {
            when Associative {
                push @checks, NotCheck.new(:path("$path/not"),
                                           check => check-for($path ~ '/not', $_, :%formats, :%add-formats));
            }
            default {
                die X::JSON::Schema::BadSchema.new:
                    :$path, :reason("The not property must be an object");
            }
        }

        with %schema<format> {
            if $_ !~~ Str {
                die X::JSON::Schema::Bad::Schema.new:
                    :$path, :reason("The format property bust be a string");
            }
            with %formats{$_} {
                push @checks, FormatCheck.new(:$path, checker => $_, format-name => %schema<format>)
            }
            with %add-formats{$_} {
                push @checks, FormatCheck.new(:$path, checker => $_, format-name => %schema<format>)
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
