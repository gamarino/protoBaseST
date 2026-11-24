"Resolution order on protoST 0.17.0, for the registry discussion (FAS, 2026-12-03).
 The same diamond as section 7 of proto_db's extensible-models tutorial:
 Lead has the parents Partner, Mailable and Schedulable; Mailable and Schedulable
 both inherit from Thread. Run: protost orden-de-resolucion.st"

Object subclass: #Thread.
Thread >> trail  ^ #('Thread').
Thread >> who  ^ 'Thread'.

Thread subclass: #Mailable.
Mailable >> trail  ^ #('Mailable'), super trail.

Thread subclass: #Schedulable.
Schedulable >> trail  ^ #('Schedulable'), super trail.
Schedulable >> who  ^ 'Schedulable'.

Object subclass: #Partner.
Partner subclass: #Lead uses: { Mailable. Schedulable }.
Lead >> trail  ^ #('Lead'), super trail.

"1. Plain lookup: Mailable does not define who; is Thread or Schedulable found first?"
('1. lookup of who: ', Lead new who) printNl.

"2. super chain: each trail calls super trail. proto_db's _super() gives
    Lead Mailable Schedulable Thread (C3, cooperative)."
('2. super chain: ', (Lead new trail inject: '' into: [:acc :each | acc, each, ' '])) printNl.

"3. An order C3 refuses (proto_db raises ProtoValidationError): X is A then B,
    Y is B then A, Z is X then Y."
Object subclass: #A.
A >> m  ^ 'A'.
Object subclass: #B.
B >> m  ^ 'B'.
A subclass: #X uses: { B }.
B subclass: #Y uses: { A }.
X subclass: #Z uses: { Y }.
('3. inconsistent hierarchy accepted, m answers: ', Z new m) printNl.
