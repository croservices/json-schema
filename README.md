NAME
====

JSON::Schema - an implementation of the [JSON Schema specification](https://json-schema.org/specification.html)

SYNOPSIS
========

    use JSON::Schema;
    my $schema = JSON::Schema.new(
        schema => from-json '{ "type": "string" }'
    );

    # Validate it and use the result as a boolean.
    say so $schema.validate("foo");     # True
    say so $schema.validate(42);        # False
    say so $schema.validate(Str);       # False

DESCRIPTION
===========

JSON::Schema is a module which allows JSON validation with set of rules described
in JSON Schema format.

Collecting all errors
---------------------

`validate` fails on the first problem it finds. When you want to report
*every* problem at once (for example, validating a configuration file at
startup), use `validate-errors`, which returns a `List` of all the
`X::JSON::Schema::Failed` exceptions instead of failing on the first one. An
empty list means the value is valid:

    my $schema = JSON::Schema.new(schema => {
        type       => 'object',
        required   => <name host>.List,
        properties => { name => { type => 'string' }, host => { type => 'string' } },
        additionalProperties => False,
    });

    my @errors = $schema.validate-errors({ host => 42, bogus => 1 });
    for @errors -> $e {
        say "$e.path(): $e.reason()";
    }
    # root: Missing required properties: 'name'
    # root: Not a string
    # root: False schema is failed   (the unknown 'bogus' key)

Aggregation continues past failures everywhere except inside the
`anyOf`/`oneOf`/`not`/`if`/`contains` keywords, which stay atomic so their
pass/fail semantics are preserved. `validate` itself is unchanged.

AUTHOR
======

Alexander Kiryuhin alexander.kiryuhin@gmail.com

COPYRIGHT AND LICENSE
=====================

Copyright © Alexander Kiryuhin alexander.kiryuhin@gmail.com

This library is free software; you can redistribute it and/or modify it under
the Artistic License 2.0.
