

using ThinModules

@thinmod module package_example
include("./c.jl")
include("./d.jl")
include("./b.jl")   


end # module
