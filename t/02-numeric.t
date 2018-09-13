use v6;
use Test;
use JSON::Schema;

my $schema;

throws-like { JSON::Schema.new(schema => { multipleOf => 'string' }) },
    X::JSON::Schema::BadSchema,
    'Having multipleOf property be a string is refused';

{
    $schema = JSON::Schema.new(schema => { type => "string", multipleOf => 3 });
    ok $schema.validate('hello'), 'Numeric checks are ignored if explicit type is not numeric';
}

{
    $schema = JSON::Schema.new(schema => { multipleOf => 3 });
    ok $schema.validate('hello'), 'Numeric checks are disabled when type is not set';
}

{
    $schema = JSON::Schema.new(schema => { type => "integer", multipleOf => 3 });
    ok $schema.validate(9), '9 is multipleOf 3';
    nok $schema.validate(10), '10 is not multipleOf 3';
}

throws-like { JSON::Schema.new(schema => { minimum => 'string' }) },
    X::JSON::Schema::BadSchema,
    'Having minimum property be a string is refused';

{
    $schema = JSON::Schema.new(schema => { type => "integer", minimum => 3 });
    ok $schema.validate(3), 'minimum 3 accepts 3';
    ok $schema.validate(4), 'minimum 3 accepts 4';
    nok $schema.validate(-3), 'minimum 3 rejects -3';
    nok $schema.validate(1), 'minimum 3 rejects 1';
}

throws-like { JSON::Schema.new(schema => { minimumExclusive => 'string' }) },
    X::JSON::Schema::BadSchema,
    'Having minimumExclusive property be a string is refused';

{
    $schema = JSON::Schema.new(schema => { type => "integer", minimumExclusive => 3 });
    ok $schema.validate(4), 'minimumExclusive 3 accepts 4';
    nok $schema.validate(3), 'minimumExclusive 3 rejects 3';
    nok $schema.validate(-3), 'minimumExclusive 3 rejects -3';
    nok $schema.validate(1), 'minimumExclusive 3 rejects 1';
}

throws-like { JSON::Schema.new(schema => { maximum => 'string' }) },
    X::JSON::Schema::BadSchema,
    'Having maximum property be a string is refused';

{
    $schema = JSON::Schema.new(schema => { type => "integer", maximum => 3 });
    ok $schema.validate(3), 'maximum 3 accepts 3';
    ok $schema.validate(2), 'maximum 3 accepts 2';
    ok $schema.validate(-3), 'maximum 3 accepts -3';
    nok $schema.validate(5), 'maximum 3 rejects 5';
}

throws-like { JSON::Schema.new(schema => { maximumExclusive => 'string' }) },
    X::JSON::Schema::BadSchema,
    'Having maximumExclusive property be a string is refused';

{
    $schema = JSON::Schema.new(schema => { type => "integer", maximumExclusive => 3 });
    ok $schema.validate(2), 'maximumExclusive 3 accepts 2';
    nok $schema.validate(3), 'maximumExclusive 3 rejects 3';
    ok $schema.validate(-3), 'maximumExclusive 3 accepts -3';
    nok $schema.validate(5), 'maximumExclusive 3 rejects 5';
}

throws-like
    { JSON::Schema.new(schema => { minLength => 4.5 }) },
    X::JSON::Schema::BadSchema,
    'Having minLength property be an non-integer is refused (Rat)';
throws-like
    { JSON::Schema.new(schema => { minLength => '4' }) },
    X::JSON::Schema::BadSchema,
    'Having minLength property be an non-integer is refused (Str)';

throws-like
    { JSON::Schema.new(schema => { maxLength => 4.5 }) },
    X::JSON::Schema::BadSchema,
    'Having maxLength property be an non-integer is refused (Rat)';
throws-like
    { JSON::Schema.new(schema => { maxLength => '4' }) },
    X::JSON::Schema::BadSchema,
    'Having maxLength property be an non-integer is refused (Str)';

{
    my $schema = JSON::Schema.new(schema => {
        type => 'string',
        minLength => 5,
        maxLength => 10
    });
    ok $schema.validate('hello'), 'String of minimum length is ok';
    nok $schema.validate('hell'), 'String below minimum length rejected';
    ok $schema.validate('hellohello'), 'String of maximum length is ok';
    nok $schema.validate('hellohello!'), 'String over maximum length rejected';
    ok $schema.validate('hello!!'), 'String between minimum and maximum ok';
}

done-testing;
