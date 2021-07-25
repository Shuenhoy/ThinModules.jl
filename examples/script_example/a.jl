

module TestB
using ThinModules


@thinmod module TestA
   include("./c.jl")
   include("./b.jl")

end
end

