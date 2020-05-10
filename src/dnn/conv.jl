using NNlib: ConvDims


# descriptor

mutable struct ConvDesc
    ptr::cudnnConvolutionDescriptor_t
end

unsafe_free!(cd::ConvDesc) = cudnnDestroyConvolutionDescriptor(cd.ptr)

Base.unsafe_convert(::Type{cudnnConvolutionDescriptor_t}, cd::ConvDesc)=cd.ptr

function cdsize(w, nd)
    isa(w, Integer) && return Cint[fill(w,nd)...]
    length(w) == nd && return Cint[reverse(w)...]
    length(w) == 2*nd && return Cint[reverse(w[nd+1:end])...]
    throw(DimensionMismatch())
end

pdsize(w, nd)=Cint[reverse(psize(w,nd))...]
function psize(w, nd)
    isa(w, Integer) && return Cint[fill(w,nd)...]
    length(w) == nd && return w
    length(w) == 2*nd && return w[1:nd]
    throw(DimensionMismatch())
end

Base.cconvert(::Type{cudnnConvolutionMode_t}, x::Bool) = x ? CUDNN_CROSS_CORRELATION : CUDNN_CONVOLUTION

function ConvDesc(T, N, padding, stride, dilation, mode, groupcount)
    cd = Ref{cudnnConvolutionDescriptor_t}()
    cudnnCreateConvolutionDescriptor(cd)
    if version() >= v"4"
        cudnnSetConvolutionNdDescriptor(cd[],N,cdsize(padding,N),cdsize(stride,N),cdsize(dilation,N),mode,cudnnDataType(T))
    elseif version() >= v"3"
        cudnnSetConvolutionNdDescriptor_v3(cd[],N,cdsize(padding,N),cdsize(stride,N),cdsize(dilation,N),mode,cudnnDataType(T))
    else
        cudnnSetConvolutionNdDescriptor(cd[],N,cdsize(padding,N),cdsize(stride,N),cdsize(dilation,N),mode)
    end
    cudnnSetConvolutionGroupCount(cd[], Cint(groupcount))
    this = ConvDesc(cd[])
    finalizer(unsafe_free!, this)
    return this
end

function ConvDesc(T, cdims::ConvDims)
    pd = NNlib.padding(cdims)
    if !all(pd[1:2:end] .== pd[2:2:end])
        @warn("CuDNN does not support asymmetric padding; defaulting to symmetric choice")
    end
    return ConvDesc(T, NNlib.spatial_dims(cdims), pd[1:2:end], NNlib.stride(cdims),
                       NNlib.dilation(cdims), NNlib.flipkernel(cdims), NNlib.group_count(cdims))
end


# wrappers

function cudnnConvolutionBiasActivationForward(y::CuArray{T,N}, x::CuArray{T,N}, w::CuArray{T,N}, bias::CuArray{T,N};
                                               alpha1=1, workspace=CU_NULL, workspace_size=0,
                                               algo=0, alpha2=0, padding=0, stride=1, dilation=1, mode=0,
                                               activationMode=CUDNN_ACTIVATION_IDENTITY, activationCoeff=0.0,
                                               activationReluNanOpt=CUDNN_NOT_PROPAGATE_NAN) where {T,N}
    cd = ConvDesc(T, N-2, padding, stride, dilation, mode)
    ad = ActivationDesc(activationMode, T(activationCoeff), activationReluNanOpt)
    cudnnConvolutionBiasActivationForward(handle(), Ref(T(alpha1)),TensorDesc(x),x,FilterDesc(w),w,cd,cudnnConvolutionFwdAlgo_t(algo),workspace,
        workspace_size,Ref(T(alpha2)),TensorDesc(bias),bias,ad,TensorDesc(y),y)
    return y
end

function cudnnConvolutionForward(y::CuArray{T,N}, x::CuArray{T,N}, w::CuArray{T,N},
                                 cdims::ConvDims; algo=0, alpha=1, beta=0) where {T,N}
    @workspace size=@argout(
            cudnnGetConvolutionForwardWorkspaceSize(
                handle(), TensorDesc(x),
                FilterDesc(w), ConvDesc(T, cdims),
                TensorDesc(y),
                cudnnConvolutionFwdAlgo_t(algo),
                out(Ref{Csize_t}()))
        )[] workspace->begin
            cudnnConvolutionForward(
                handle(), Ref(T(alpha)), TensorDesc(x), x, FilterDesc(w), w,
                ConvDesc(T,cdims), cudnnConvolutionFwdAlgo_t(algo), workspace,
                sizeof(workspace), Ref(T(beta)), TensorDesc(y), y)
        end
    return y
end

function cudnnConvolutionBackwardData(dx::CuArray{T,N}, w::CuArray{T,N}, dy::CuArray{T,N},
                                      cdims::ConvDims; algo=0, alpha=1, beta=0) where {T,N}
    @workspace size=@argout(
            cudnnGetConvolutionBackwardDataWorkspaceSize(
                handle(), FilterDesc(w),
                TensorDesc(dy), ConvDesc(T, cdims), TensorDesc(dx),
                cudnnConvolutionBwdDataAlgo_t(algo),
                out(Ref{Csize_t}()))
        )[] workspace->begin
            cudnnConvolutionBackwardData(
                handle(), Ref(T(alpha)), FilterDesc(w), w,
                TensorDesc(dy), dy, ConvDesc(T, cdims),
                cudnnConvolutionBwdDataAlgo_t(algo),
                workspace, sizeof(workspace),
                Ref(T(beta)), TensorDesc(dx), dx)
        end
    return dx
end

function cudnnConvolutionBackwardFilter(dw::CuArray{T,N}, x::CuArray{T,N}, dy::CuArray{T,N},
                                        cdims::ConvDims; algo=0, alpha=1, beta=0) where {T,N}
    @workspace size=@argout(
            cudnnGetConvolutionBackwardFilterWorkspaceSize(
                handle(), TensorDesc(x),
                TensorDesc(dy),
                ConvDesc(T, cdims),
                FilterDesc(dw),
                cudnnConvolutionBwdFilterAlgo_t(algo),
                out(Ref{Csize_t}()))
        )[] workspace->begin
            cudnnConvolutionBackwardFilter(
                handle(), Ref(T(alpha)), TensorDesc(x), x,
                TensorDesc(dy), dy, ConvDesc(T, cdims),
                cudnnConvolutionBwdFilterAlgo_t(algo), workspace,
                sizeof(workspace), Ref(T(beta)), FilterDesc(dw), dw)
        end
    return dw
end

function cudnnConvolutionBackwardBias(db::CuArray{T,N}, dy::CuArray{T,N}; alpha=1, beta=0) where {T,N}
    cudnnConvolutionBackwardBias(handle(), Ref(T(alpha)), TensorDesc(dy), dy, Ref(T(beta)), TensorDesc(db), db)
    return db
end
