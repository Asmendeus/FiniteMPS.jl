"""
    addIntr3!(Root::InteractionTreeNode,
         Op::NTuple{3,AbstractTensorMap},
         si::NTuple{3,Int64},
         strength::Number;
         Obs::Bool = false,
         Z::Union{Nothing,AbstractTensorMap} = nothing,
         name::NTuple{3,Union{Symbol,String}} = (:A, :B, :C)) -> nothing

    addIntr3!(Tree::InteractionTree, args...) = addIntr3!(Tree.Root.children[1], args...)

Add a 3-site interaction `Op` at site `si` (3tuple) to a given interaction tree. If Z is given, assume operators in `Op` are fermionic and apply the Z transformation automatically.

    addIntr3!(Root::InteractionTreeNode,
         A::LocalOperator,
         B::LocalOperator,
         C::LocalOperator,
         strength::Number,
         Z::Union{Nothing,AbstractTensorMap};
         value = nothing) -> nothing

Expert version, each method finally reduces to this one. The `value` will be stored in the last node.

Note if there exist repeated si, it will recurse to `addIntr2!` or `addIntr1!` automatically.
"""
function addIntr3!(Root::InteractionTreeNode, Op::NTuple{3,AbstractTensorMap}, si::NTuple{3,Int64}, strength::Number;
     Obs::Bool=false,
     Z::Union{Nothing,AbstractTensorMap}=nothing,
     name::NTuple{3,Union{Symbol,String}}=(:A, :B, :C))

    # Convert names to strings
    name = string.(name)

    strength == 0 && return nothing
    value = Obs ? (prod(name), si...) : nothing

    (A, B, C) = map(1:3) do i
        LocalOperator(Op[i], name[i], si[i])
    end

    # Ensure site indices are in ascending order
    if si[1] > si[2]
        A, B = _swap(A, B)
        si = (si[2], si[1], si[3])
        !isnothing(Z) && (strength *= -1)
    end
    if si[2] > si[3]
        B, C = _swap(B, C)
        si = (si[1], si[3], si[2])
        !isnothing(Z) && (strength *= -1)
    end
    if si[1] > si[2]
        A, B = _swap(A, B)
        si = (si[2], si[1], si[3])
        !isnothing(Z) && (strength *= -1)
    end

    _addtag!(A, B, C)

    # Reduce to two-site if indices overlap
    if si[1] == si[2]
        return addIntr2!(Root, A * B, C, strength, Z; value=value)
    elseif si[2] == si[3]
        return addIntr2!(Root, A, B * C, strength, Z; value=value)
    end

    return addIntr3!(Root, A, B, C, strength, Z; value=value)
end

function addIntr3!(Root::InteractionTreeNode,
     A::LocalOperator, B::LocalOperator, C::LocalOperator,
     strength::Number, Z::Union{Nothing,AbstractTensorMap};
     value=nothing)

    @assert A.si < B.si < C.si

    #         C
    #     B
    # A Z Z

    !isnothing(Z) && _addZ!(B, Z)

    current_node = Root
    si = 1
    pspace = getPhysSpace(A)

    while si < C.si
        if si == A.si
            Op_i = A
        elseif si == B.si
            Op_i = B
        elseif !isnothing(Z) && A.si < si < B.si
            Op_i = LocalOperator(Z, :Z, si)
        else
            Op_i = IdentityOperator(pspace, si)
        end

        idx = findfirst(current_node.children) do x
            x.Op ≠ Op_i && return false
            if hastag(x.Op) && hastag(Op_i)
                 x.Op.tag ≠ Op_i.tag && return false
            end
            return true
        end
        if isnothing(idx)
            addchild!(current_node, Op_i)
            current_node = current_node.children[end]
        else
            current_node = current_node.children[idx]
            # replace the tag
            hastag(current_node.Op) && (current_node.Op.tag = Op_i.tag)
        end
        si += 1
    end

    # Add the last operator (C)
    idx = findfirst(x -> x.Op == C, current_node.children)
    if isnothing(idx)
        addchild!(current_node, C, value)
        current_node.children[end].Op.strength = strength
    else
        if !isnothing(value)
            current_node.children[idx].value = value
        end
        _update_strength!(current_node.children[idx], strength) && deleteat!(current_node.children, idx)
    end

    return nothing
end

_addtag!(::LocalOperator{1, 1}, ::LocalOperator{1, 1}, ::LocalOperator{1, 1}) = nothing

function _addtag!(A::LocalOperator{1,2}, B::LocalOperator{2,2}, C::LocalOperator{2,1})
    name = map(x -> x.name, [A, B, C])
    for i = 2:3 # make sure each name is unique
         if any(==(name[i]), view(name, 1:i-1))
              name[i] = name[i] * "$i"
         end
    end
    A.tag = (("phys",), ("phys", "$(name[1])<-$(name[2])"))
    B.tag = (("$(name[1])<-$(name[2])", "phys"), ("phys", "$(name[2])<-$(name[3])"))
    C.tag = (("$(name[2])<-$(name[3])", "phys"), ("phys",))
    return nothing
end