use v6;
use Test;
use JSON::Schema;

my $schema;

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

done-testing;
