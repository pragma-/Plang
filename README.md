# Plang
Plang is a pragmatic scripting language written in Perl.

Why? Because I need a small, yet useful, scripting language I can embed into
some Perl scripts I have; notably [PBot](https://github.com/pragma-/pbot), an
IRC bot that I've been tinkering with for quite a while. Check out its Plang
[plugin](https://github.com/pragma-/pbot/blob/master/Plugins/Plang.pm) and the
plugin's [documentation](https://github.com/pragma-/pbot/blob/master/doc/Plugins/Plang.md)!

I want to be able to allow text from external sources (e.g. untrusted users)
to be safely interpreted in a sandbox environment with access to selectively
exposed Perl subroutines, with full control over how deeply functions are allowed
to recurse, et cetera.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

For more details see [the documentation](doc/).
