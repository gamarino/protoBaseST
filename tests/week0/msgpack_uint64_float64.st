"EXPECT: ok 4"
"Week-0 check (Spec 9): protoST's MessagePack writes the integers and floats that format 4 needs
 with the widest forms ProtoBase's msgpack uses: uint64 (0xcf) and float64 (0xcb)."
| check |
check := [:value :expected |
    ((MessagePack encode: value) hex = expected)
        ifFalse: [Error signal: 'msgpack mismatch for ', value printString, ': ',
                  (MessagePack encode: value) hex]].
check value: (2 raisedTo: 63) value: 'cf8000000000000000'.
check value: (2 raisedTo: 64) - 1 value: 'cfffffffffffffffff'.
check value: 1.5 value: 'cb3ff8000000000000'.
check value: 0.0 value: 'cb0000000000000000'.
'ok 4' displayNl
