using LinearAlgebra, Test
@testset "CUBLASMG" begin

using CuArrays.CUBLASMG
using CUDAdrv

voltas    = filter(dev->occursin("V100", name(dev)), collect(CUDAdrv.devices()))
pascals    = filter(dev->occursin("P100-PCIE", name(dev)), collect(CUDAdrv.devices()))
m = 8192
n = div(8192, 2)
k = 8192*2
devs = voltas[1:1]
CUBLASMG.cublasMgDeviceSelect(CUBLASMG.mg_handle(), length(devs), devs)
@testset "element type $elty" for elty in [Float32, Float64]
    @testset "mg_gemm!" begin
        GC.enable(false)
        alpha = convert(elty,1.1)
        beta  = convert(elty,0.0)
        C = zeros(elty, m, n)
        A = rand(elty, m, k)
        B = rand(elty, k, n)
        d_C = copy(C)
        d_C = CUBLASMG.mg_gemm!('N','N',alpha,A,B,beta,d_C, devs=devs)
        # compare
        h_C = alpha*A*B + beta*C
        @test d_C ≈ h_C

        C = zeros(elty, m, n)
        A = rand(elty, k, m)
        B = rand(elty, k, n)
        d_C = copy(C)
        d_C = CUBLASMG.mg_gemm!('T','N',alpha,A,B,beta,d_C, devs=devs)
        # compare
        h_C = alpha*transpose(A)*B + beta*C
        @test d_C ≈ h_C

        C = zeros(elty, m, n)
        A = rand(elty, m, k)
        B = rand(elty, n, k)
        d_C = copy(C)
        d_C = CUBLASMG.mg_gemm!('N','T',alpha,A,B,beta,d_C, devs=devs)
        # compare
        h_C = alpha*A*transpose(B) + beta*C
        @test d_C ≈ h_C
        GC.enable(true)
    end
end # elty

end # cublasmg testset
