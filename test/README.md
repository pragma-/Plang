# Unit tests
These are some unit tests to ensure that Plang is behaving correctly.

You can run each test with (assuming you haven't installed Plang to your PATH):

    $ ../bin/runtests [file...]

where `[file...]` is an optional list of files to test. If omitted, all files
in this directory will be tested.

E.g., to test `operators.pt` and `types.pt` you can run:

    $ ../bin/runtests operators.pt types.pt

See `../bin/runtests -h` for more options.
