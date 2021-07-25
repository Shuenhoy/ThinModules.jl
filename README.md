
*WARNING: this package is still in early stage.*
- - -
# ThinModules.jl

This package helps you manage your dependence-relationship
between your modules. It will first traverse over your whole
source tree that formed by your `include`, then the
dependence-relationship is found from `using`/`import`
declarations. Finally, all the modules would be evaluated by
the topological sorting order.

The goal is to keep things as similar to standard Julia as
possible. All you need to do is using the macro `@thinmod`
to wrap your entry module.


## Installation

```
] add "https://github.com/Shuenhoy/ThinModules.jl"
```

## Usage
```julia
@thinmod module MyModule
# all submodules inside can have free orders. ThinModules would do the re-order.
    module B
        import ..C
        @show C.c
    end
    module C
        c = 3
    end
end
```

You can try the [the example](./examples/).

## Notes
* ThinModules is for "module dependency" and does not assume
  a file-module mapping. If you just include other files
  without wrapping them with an explicit module declaration,
  nothing would happen.

## Limitations
* Any dependency must be used by `using/import`. If you want
  to use module `Main.A.C`, you must directly `using/import
  Main.A.C`. You cannot `import Main.A` then use `A.C`.
* If you want to use it on a package's top module, you would see a
  warning:
```
┌ Warning: Package Base does not have ThinModules in its dependencies:
│ - If you have Base checked out for development and have
│   added ThinModules as a dependency but haven't updated your primary
│   environment's manifest file, try `Pkg.resolve()`.
│ - Otherwise you may need to report an issue with Base
└ Loading ThinModules into Base from project dependency, future warnings for Base are suppressed.
```
* Only direct `using/import`, `include`, `module` are
  processed. If you have some fancy meta-programming, it
  could fail.
