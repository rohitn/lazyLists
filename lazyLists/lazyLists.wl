(* Wolfram Language Package *)

(* Created by the Wolfram Workbench 18-Sep-2018 *)
ClearAll["lazyLists`*", "lazyLists`Private`*"];

BeginPackage["lazyLists`"]
(* Exported symbols added here with SymbolName::usage *) 

lazyList::usage = "lazyList is linked list data structure that should contain 2 elements: the first is the first element, the second a held expression that will generate the next linked list when evaluated.
You can extract these elements explicitely with First and Last/Rest. Part and Take will not work because they have been overloaded with special functionalities when used on lazyList.
lazyList[list] or lazyList[Hold[var]] is a special constructor that generates a lazyList from an ordinary list";

lazyRange::usage = "lazyRange[] is a lazy representation of the Integers from 1 to \[Infinity]. lazyRange[min, delta] represents values values from min onwards in steps of delta. lazyRange has no upper limit";

lazyPowerRange::usage = "lazyPowerRange[min, r] is the infinite list {min, r \[Times] min, r^2 \[Times] min, ...}";

lazyNestList::usage = "lazyNestList[f, elem] is the infinite list {elem, f[elem], f[f[elem]], ...} starting with elem and generated by iterating f repeatedly";

lazyStream::usage = "lazyStream[streamObject] creates a lazyList that streams from streamObject. These streams will stop automatically when EndOfFile is reached";

lazyConstantArray::usage = "lazyConstantArray[elem] produces an infinite list of copies of elem";

lazyMapThread::usage = "lazyMapThread[f, {lz1, lz2, ...}] is similar to MapThread, except all elements from the lazyLists are fed to the first slot of f as a regular List";

lazyTranspose::usage = "lazyTranspose[{lz1, lz2, ...}] creates a lazyList with tuples of elements from lz1, lz2, etc. 
Equivalent to lazyMapThread[Identity, {lz1, lz2, ...}]";

lazyPartMap::usage = "lazyPartMap[l, {i, j, k, ...}] is equivalent to Map[Part[l, {#}]&, {i, j, k, ...}] but faster";

lazyFinitePart::usage = "lazyFinitePart[lz, i, j, k,...] directly extracts Part from finite and periodic lazyLists without having to traverse the lazyList element-by-element. 
It is equivalent to Part[list, i, j, k, ...]";

lazyFiniteTake::usage = "lazyFiniteTake[lz, spec] directly applies Take to finite lazyLists and periodic lazyLists without having to traverse the lazyList element-by-element. 
It is equivalent to Take[list, spec]";

lazySetState::usage = "lazySetState[lz, index] with lz a supported lazyList returns a lazyList at the specified index. 
Finite lists, lazyPeriodicList and lists generated with lazyGenerator, lazy(Power)Range, and lazyNestList are supported";

lazyGenerator::usage = "lazyGenerator[f, start, min, max, step] generates a lazyList that applies f to values {start, start + step, start + 2 step, ...} for values between min and max (which are allowed to be infinite).
When min and max are both infinite, symbolic values for start and step are allowed";

lazyPeriodicList::usage = "lazyPeriodicList[list] is an infinite lazyList that cycles through the values in list periodically";

$lazyIterationLimit::usage = "Iteration limit used for finding successive elements in a lazy list";

Begin["`Private`"]
(* Implementation of the package *)

$lazyIterationLimit = Infinity;

Attributes[lazyList] = {HoldRest};
lazyList /: Rest[lazyList[_, tail_]] := tail;

lazyList[list_List] := Module[{
    listVar = list
},
    lazyList[Hold[listVar]]
];

Attributes[lazyFiniteList] = {HoldFirst};
lazyList[Hold[list_Symbol]] := lazyFiniteList[list, 1];

With[{
    msgs = {Part::partw}
},
    (* Don't test patterns for performance. It's up to the user to make sure nothing illegal ends up in lazyFiniteList if they decide to use it *)
    lazyFiniteList[list_, i_] := Quiet[
        Check[
            lazyList[list[[i]], lazyFiniteList[list, i + 1]], 
            lazyList[],
            msgs
        ],
        msgs
    ]
];

lazySetState[lazyList[_, l : lazyFiniteList[list_, _]], index_Integer] /; 0 < index <= Length[list] :=
    lazyFiniteList[list, index];

lazySetState[l : lazyList[_, lazyFiniteList[list_, _]], index_Integer] /; -Length[list] <= index < 0 := 
    lazySetState[l, index + Length[list] + 1];

lazySetState[l : lazyList[_, lazyFiniteList[list_, _]], index_Integer] := (
    Message[Part::partw, index, Short[l]];
    l
);

lazyGenerator[
    f_,
    start : _ : 1,
    min : _ : DirectedInfinity[-1], max : _ : DirectedInfinity[1], step : _ : 1
] := Switch[ {min, max, start, step},
    {DirectedInfinity[-1], DirectedInfinity[1], __},
        twoSidedGenerator[f, start, step],
    {DirectedInfinity[-1], _?NumericQ, _?NumericQ, _?NumericQ},
        leftSidedGenerator[f, start, max, step],
    {_?NumericQ, DirectedInfinity[1], _?NumericQ, _?NumericQ},
        rightSidedGenerator[f, start, min, step],
    {_?NumericQ, _?NumericQ,_?NumericQ, _?NumericQ},
        finiteGenerator[f, start, min, max, step],
    _,
        lazyList[]
];

twoSidedGenerator[f_, pos_, step_] := lazyList[
    f[pos],
    twoSidedGenerator[f, pos + step, step]
];

leftSidedGenerator[f_, pos_, max_, step_] /; pos <= max := lazyList[
    f[pos],
    leftSidedGenerator[f, pos + step, max, step]
];
leftSidedGenerator[___] := lazyList[];

rightSidedGenerator[f_, pos_, min_, step_] /; min <= pos := lazyList[
    f[pos],
    rightSidedGenerator[f, pos + step, min, step]
];
rightSidedGenerator[___] := lazyList[];

finiteGenerator[f_, pos_, min_, max_, step_] /; Between[pos, {min, max}] := lazyList[
    f[pos],
    finiteGenerator[f, pos + step, min, max, step]
];
finiteGenerator[___] := lazyList[];

lazySetState[
    l : lazyList[
        _,
        (gen : (twoSidedGenerator | leftSidedGenerator | rightSidedGenerator | finiteGenerator))[f_, pos_, rest___]
    ],
    index_
] := Replace[
    gen[f, index, rest],
    {
        lazyList[] :> (Message[Part::partw, index, Short[l]]; l)
    }
];


(* For efficiency reasons, these lazy list generatorss are defined by self-referential anynomous functions. Note that #0 refers to the function itself *)
lazyRange[start : _ : 1, step : _ : 1] /; !TrueQ[step == 0] := Function[
    lazyList[#1, #0[#2 + #1, #2]]
][start, step];

lazyRange[start_, step_ /; TrueQ[step == 0]] := lazyConstantArray[start];

lazyPowerRange[start_, r_ /; !TrueQ[r == 1]] := Function[
    lazyList[#1, #0[#2 * #1, #2]]
][start, r];

lazyPowerRange[min_, r_ /; TrueQ[r == 1]] := lazyConstantArray[min]

lazyNestList[f_, elem_] := Function[
    lazyList[
        #1,
        #0[f[#1], #2 + 1]
    ]
][elem, 1];

(*lazySetState definition for lazyRange and lazyPowerRange and lazyNestList *)
lazySetState[
    lazyList[_, (f : Function[lazyList[#1, #0[_, _]]])[_, step_]],
    ind_
] := f[ind, step];

lazyStream[stream_InputStream] := Function[
    With[{
        read = Read[#1]
    },
        lazyList[
            read,
            If[ read =!= EndOfFile,
                #0[#1, #2 + 1], (* Increase an iterator to make sure that ReplaceRepeated in Take doesn't stop *)
                lazyList[] (* return an empty lazyList to end stream *)
            ]
        ]
    ]
][stream, 1];

lazyConstantArray[const_] := Function[
    lazyList[
        const,
        (* Increase an iterator to make sure that ReplaceRepeated in Take doesn't stop *)
        #0[#1 + 1]
    ]
][1];


Attributes[lazyPeriodicListInternal] = {HoldFirst};
lazyPeriodicListInternal[list_, i_, max_] := lazyList[
    list[[i]],
    lazyPeriodicListInternal[list, Mod[i, max] + 1, max]
];

lazyPeriodicList[list_List] := Module[{
    listVar = list
},
    lazyPeriodicList[Hold[listVar]]
];
lazyPeriodicList[Hold[list_Symbol]] := lazyPeriodicListInternal[list, 1, Length[list]];

lazySetState[lazyList[_, lazyPeriodicListInternal[list_, _, max_]], index_Integer] := 
    lazyPeriodicListInternal[list, Mod[index - UnitStep[index], max] + 1, max];


lazyList::notFinite = "lazyList `1` cannot be recognised as a finite list";
lazySetState[l_lazyList, _] := (Message[lazyList::notFinite, Short[l]]; l)

lazyFinitePart[lazyList[_, (lazyFiniteList | lazyPeriodicListInternal)[list_, __]], spec__] := Part[list, spec];
lazyFinitePart[l_lazyList, _] := (Message[lazyList::notFinite, Short[l]]; $Failed);

lazyFiniteTake[lazyList[_, (lazyFiniteList | lazyPeriodicListInternal)[list_, __]], spec_] := Take[list, spec];
lazyFiniteTake[l_lazyList, _] := (Message[lazyList::notFinite, Short[l]]; $Failed);

(* Set threading behaviour for lazyLists to make it possible to add and multiply them and use powers on them *)
lazyList /: (op : (Plus | Times | Power | Divide | Subtract))[first___, l__lazyList, rest___] :=
    Thread[
        Unevaluated[op[first, l, rest]],
        lazyList
    ];

(* Elements from lazyLists are extracted by repeatedly evaluating the next element and sowing the results *)
lazyList /: Take[l_lazyList, n_Integer?Positive] := lazyList @@ MapAt[
    First[#, {}]&,
    Reverse @ Reap[
        Replace[
            Quiet[
                Block[{$IterationLimit = $lazyIterationLimit},
                    ReplaceRepeated[
                        l,
                        {
                            lazyList[first_, tail_] :> (Sow[first, "take"]; tail)
                        },
                        MaxIterations -> n - 1
                    ]
                ],
                {ReplaceRepeated::rrlim}
            ],
            (* The last element should only be Sown without evaluating the tail *)
            lazyList[first_, tail_] :> (Sow[first, "take"]; lazyList[first, tail]) 
        ],
        "take"
    ],
    1
];

lazyList /: Take[l_lazyList, {m_Integer?Positive, n_Integer?Positive}] /; n < m := Replace[
    Take[l, {n, m}],
    {
        lazyList[list_List, rest_] :> lazyList[Reverse[list], rest]
    }
];

lazyList /: Take[l_lazyList, {m_Integer?Positive, n_Integer?Positive}] /; n > m := Replace[
    Quiet[l[[{m}]], {Part::partw}],
    {
        lz : lazyList[_, _] :> Take[lz, n - m + 1],
        _ -> lazyList[]
    }
];

lazyList /: TakeWhile[l_lazyList, function_, OptionsPattern[MaxIterations -> Infinity]] := lazyList @@ MapAt[
    First[#, {}]&,
    Reverse @ Reap[
        Quiet[
            Catch[
                Block[{$IterationLimit = $lazyIterationLimit},
                    ReplaceRepeated[
                        l,
                        {
                            lazyList[first_, tail_] :> If[function[first]
                                ,
                                Sow[first, "take"];
                                tail
                                ,
                                Throw[lazyList[first, tail], "break"],
                                Throw[lazyList[first, tail], "break"]
                            ]
                        },
                        MaxIterations -> OptionValue[MaxIterations]
                    ]
                ],
                "break"
            ],
            {ReplaceRepeated::rrlim}
        ],
        "take"
    ],
    1
];

lazyList /: Part[lazyList[___], 0 | {0}] := lazyList;
lazyList /: Part[lazyList[first_, _], 1] := first;
lazyList /: Part[l : lazyList[_, _], {1}] := l;
lazyList /: Part[l_lazyList, n_Integer] := First[Part[l, {n}], $Failed];

lazyList /: Part[l_lazyList, Span[m_Integer, n_Integer]] := Replace[
    Take[l, {m, n}],
    {
        lazyList[] | lazyList[_, lazyList[]] :> (Message[Part::partw, Max[m, n], Short[l]]; $Failed)
    }
];

lazyList /: Part[l_lazyList, Span[m_Integer, n_Integer, incr_Integer]] := Part[
    l,
    Range[m, n, incr]
];

lazyList /: Part[l_lazyList, indices : {__Integer}] := Catch[
    Module[{
        sortedIndices = Sort[indices],
        eval
    },
        lazyList[
            Part[
                FoldPairList[
                    Function[
                        eval = Check[Part[#1, {#2}], Throw[$Failed, "part"], {Part::partw}];
                        {
                            First[eval], (* emit the value at this position *)
                            eval (* and return the lazyList to the next iteration *)
                        }
                    ],
                    l,
                    Prepend[Differences[sortedIndices] + 1, First[sortedIndices]]
                ],
                Ordering[indices]
            ],
            Evaluate[eval]
        ]
    ],
    "part"
];

lazyPartMap[l_lazyList, indices : {__Integer}] := Module[{
    sortedIndices = Sort[indices]
},
    Part[
        FoldList[
            Function[
                Part[#1, {#2}]
            ],
            Part[l, sortedIndices[[{1}]]],
            Differences[sortedIndices] + 1
        ],
        Ordering[indices]
    ]
];

lazyList /: Part[l_lazyList, {n_Integer}] := Replace[
    Quiet[
        Block[{$IterationLimit = $lazyIterationLimit},
            ReplaceRepeated[
                l,
                {
                    lazyList[first_, tail_] :> tail
                },
                MaxIterations -> n - 1
            ]
        ],
        {ReplaceRepeated::rrlim}
    ],
    {
        lazyList[] :> (Message[Part::partw, n, Short[l]]; $Failed)
    }
];

lazyList /: Map[f_, lazyList[first_, tail_]] := lazyList[
    f[first],
    Map[f, tail]
];

lazyList /: MapIndexed[f_, lazyList[first_, tail_], index : (_Integer?Positive) : 1] := lazyList[
    f[first, index],
    MapIndexed[f, tail, index + 1]
];

lazyMapThread[f_, list : {lazyList[_, _]..}] := lazyList[
    f[list[[All, 1]]],
    lazyMapThread[f, list[[All, 2]]]
];

lazyMapThread[_, _] := lazyList[];

lazyTranspose[list : {__lazyList}] := lazyMapThread[Identity, list];

lazyList /: FoldList[f_, lazyList[first_, tail_]] := FoldList[f, first, tail];

lazyList /: FoldList[f_, current_, lazyList[first_, tail_]] := lazyList[
    current,
    FoldList[f, f[current, first], tail]
];

lazyList /: FoldList[f_, current_, empty : lazyList[]] := lazyList[current, empty];

lazyList /: Cases[l_lazyList, patt_] := Module[{
    case
 },
    (* Define helper function to match patterns faster *)
    case[lazyList[first : patt, tail_]] := lazyList[first, case[tail]];
    case[lazyList[first_, tail_]] := case[tail];
    
    case[l]
];

lazyList /: Pick[l_lazyList, select_lazyList, patt_] := Module[{
    pick
},
    (* Define helper function, just like with Cases *)
    pick[lazyList[first_, tail1_], lazyList[match : patt, tail2_]] :=
        lazyList[first, pick[tail1, tail2]];
    pick[lazyList[first_, tail1_], lazyList[first2_, tail2_]] :=
        pick[tail1, tail2];
        
    pick[l, select] 
];

lazyList /: Select[lazyList[first_, tail_], f_] /; f[first] := lazyList[first, Select[tail, f]];
lazyList /: Select[lazyList[first_, tail_], f_] := Select[tail, f];



End[]

EndPackage[]

