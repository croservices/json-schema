use OpenAPI::Schema::Validate;
use Test;
use JSON::Schema;

throws-like
    { JSON::Schema.new(schema => { minItems => 4.5 }) },
    X::JSON::Schema::BadSchema,
    'Having minItems property be an non-integer is refused (Rat)';
throws-like
    { JSON::Schema.new(schema => { maxItems => '4' }) },
    X::JSON::Schema::BadSchema,
    'Having maxItems property be an non-integer is refused (Str)';
throws-like
    { JSON::Schema.new(schema => { uniqueItems => 'yes' }) },
    X::JSON::Schema::BadSchema,
    'Having uniqueItems property be an non-boolean is refused (Str)';

{
    my $schema = JSON::Schema.new(schema => {
        type => 'array',
        minItems => 2,
        maxItems => 4
    });
    nok $schema.validate([1]), 'Array below minimum length rejected';
    ok $schema.validate([1,2]), 'Array of minimum length rejected';
    ok $schema.validate([1,2,3,4]), 'Array of maximum length accepted';
    nok $schema.validate([1,2,3,4,5]), 'Array over maximum length rejected';
    nok $schema.validate('string'), 'String instead of array rejected';
}

{
    my $schema = JSON::Schema.new(schema => {
        type => 'array',
        uniqueItems => False
    });
    ok $schema.validate([1, 1]), 'Array with duplicates accepted';
    $schema = JSON::Schema.new(schema => {
        type => 'array',
        uniqueItems => True
    });
    ok $schema.validate([{a => 1, b => 2}, {c => 1, a => 1}]), 'Array of objects without duplicates accepted';
    nok $schema.validate([{a => 1, b => 2}, {a => 1, b => 2}]), 'Array of objects with duplicates rejected';
}

done-testing;
