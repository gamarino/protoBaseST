"EXPECT: ok 10"
"Week-0 check of the cluster plan (Task 1): the values cluster mode computes with. (1-4) the
 MessagePack round trip of 2^56, 2^62 - 1, 2^63 and 2^64 - 1 (decode of encode is equal, and
 compares right against 2^56 - 1); (5-6) floor division of a negative number, and the ballot
 formula built on it; (7) two Random seed: 42 generators give the same 100 values; (8) HMAC-SHA-256
 of RFC 4231 test case 2; (9) 8 random bytes read as an unsigned integer and masked with
 2^62 - 1 give a non-negative Integer below 2^62; (10) Atom value:ifCurrent: answers true on the
 current value and false on a stale one."
| passed check below big |
passed := 0.
check := [:name :aBoolean |
    aBoolean == true ifFalse: [Error signal: 'failed: ' , name].
    passed := passed + 1].
below := (2 raisedTo: 56) - 1.

{2 raisedTo: 56. (2 raisedTo: 62) - 1. 2 raisedTo: 63. (2 raisedTo: 64) - 1} do: [:v | | back |
    back := MessagePack decode: (MessagePack encode: v).
    check value: 'MessagePack round trip of ' , v printString
          value: (back = v and: [(back < below) not and: [below < back]])].

check value: '-5 // 4096 = -1' value: -5 // 4096 = -1.
check value: 'the ballot formula' value: (0 - 5) // 4096 + 1 * 4096 + 5 = 5.

check value: 'Random seed: 42 is reproducible' value: [ | a b |
    a := Random seed: 42.
    b := Random seed: 42.
    ((1 to: 100) collect: [:i | a next]) asArray = ((1 to: 100) collect: [:i | b next]) asArray] value.

check value: 'HMAC-SHA-256, RFC 4231 test case 2'
      value: (HMAC sha256Key: 'Jefe' utf8Encoded message: 'what do ya want for nothing?' utf8Encoded) hex
             = '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'.

big := ((ByteArray randomBytes: 8) unsignedLong64At: 1 bigEndian: true) bitAnd: (2 raisedTo: 62) - 1.
check value: '8 random bytes masked with 2^62 - 1'
      value: ((big isKindOf: Integer) and: [big >= 0 and: [big < (2 raisedTo: 62)]]).

check value: 'Atom value:ifCurrent:' value: [ | atom current |
    atom := Atom on: 'first'.
    current := atom value.
    (atom value: 'second' ifCurrent: current) == true
        and: [(atom value: 'third' ifCurrent: current) == false
        and: [atom value = 'second']]] value.

('ok ' , passed printString) displayNl
