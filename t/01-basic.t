use v6;
use Test;
use JSON::Schema;

throws-like { JSON::Schema.new(schema => { type => 42 }) },
    X::JSON::Schema::BadSchema,
    'Having type property be an integer is refused';
throws-like { JSON::Schema.new(schema => { type => 'namber' }) },
    X::JSON::Schema::BadSchema,
    'Having type property be an invalid type is refused';

my $schema;
{
    $schema = JSON::Schema.new(schema => {:type('string')});
    ok $schema.validate('hello'), 'Simple string validation accepts a string';
    nok $schema.validate(42), 'Simple string validation rejects an integer';
    nok $schema.validate(Str), 'Simple string validation rejects a type object';
}

throws-like { JSON::Schema.new(schema => { type => ('string', 1) }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, non-strings are rejected (Int)';
throws-like { JSON::Schema.new(schema => { type => ('string', Str) }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, non-strings are rejected (Str type object)';
throws-like { JSON::Schema.new(schema => { type => ('string', 'string') }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, items must be unique';
throws-like { JSON::Schema.new(schema => { type => ('string', 'namber') }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, items must be withing allowed type range';

{
    $schema = JSON::Schema.new(schema => { type => ('string', 'integer') });
    ok $schema.validate('hello'), 'Simple string&integer validation accepts a string';
    ok $schema.validate(42), 'Simple string&integer validation accepts an integer';
    nok $schema.validate(666.666), 'Simple string&integer validation rejects a number';
    nok $schema.validate(Rat), 'Simple string&integer validation rejects a type object (Rat)';
}

{
    $schema = JSON::Schema.new(schema => { type => 'null' });
    ok $schema.validate(Nil), 'Simple null validation accepts a Nil';
    nok $schema.validate(42), 'Simple null validation rejects an integer';
}

{
    $schema = JSON::Schema.new(schema => { type => 'boolean' });
    ok $schema.validate(True), 'Simple boolean validation accepts True';
    ok $schema.validate(False), 'Simple boolean validation accepts False';
    nok $schema.validate(Bool), 'Simple boolean validation rejects an Bool type object';
    nok $schema.validate(42), 'Simple boolean validation rejects an integer';
}

{
    $schema = JSON::Schema.new(schema => { type => 'object' });
    ok $schema.validate({}), 'Simple object validation accepts empty hash';
    ok $schema.validate((one => 1).Hash), 'Simple object validation accepts hash';
    nok $schema.validate(42), 'Simple object validation rejects an integer';
}

{
    $schema = JSON::Schema.new(schema => { type => 'array' });
    ok $schema.validate(()), 'Simple array validation accepts empty list';
    ok $schema.validate((1, 2, 3)), 'Simple array validation accepts list';
    nok $schema.validate(42), 'Simple array validation rejects an integer';
}

{
    $schema = JSON::Schema.new(schema => { type => 'number' });
    ok $schema.validate(666.666), 'Simple number validation accepts a number';
    nok $schema.validate(42), 'Simple number validation rejects an integer';
    nok $schema.validate(Any), 'Simple number validation rejects a type object';
}

{
    $schema = JSON::Schema.new(schema => { enum => (1, Nil, 'String') });
    ok $schema.validate(Nil), 'Nil is accepted';
    ok $schema.validate(1), 'Correct integer is accepted';
    nok $schema.validate(2), 'Incorrect integer is rejected';
    ok $schema.validate('String'), 'Correct string is accepted';
    nok $schema.validate('Strign'), 'Incorrect string is rejected';
}

{
    $schema = JSON::Schema.new(schema => { const => 1, type => 'integer' });
    ok $schema.validate(1), 'Constant 1 is accepted';
    nok $schema.validate(2), 'Incorrect constant value is rejected 1';
    nok $schema.validate(Int), 'Incorrect constant value is rejected 2';
}

done-testing;
