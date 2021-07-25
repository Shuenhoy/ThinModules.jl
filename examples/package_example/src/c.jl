module TestC

import ..TestB.c as y
import package_example.TestD:d as z

function print_vars()
    @show y
    @show z
end

end