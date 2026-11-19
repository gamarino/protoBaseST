"-- pager.st: in-process pages of one plan, PBPager --

A port of proto_db's proto_db/query/pager.py at v2.0.0rc4, class Pager (lines 136-227; decision
D56, rulings R77 and R77a), less what spec 3.2 defers (rulings IQ3 and IQ7): portable pager tokens
(token, Transaction.pager, Snapshot.pager, Database.resume_pager) and the query result cache (the
cache argument). The design spec's section 5.7 states the behaviour.

A PBPager holds one plan, built on one version of a collection, and serves page k of it, k from 0
(ruling CR7, as proto_db's page and PBList positions). Every page comes from the same immutable
versions, so a pager never shows a row twice and never skips one, whatever is committed or written
meanwhile, and it needs no lock and no pinning: every committed version stays readable.

  PBPager on: aSource pageSize: n
      aSource is a PBQueryPlan, a PBQuery (its plan) or a PBIndexedCollection (its scan,
      asQueryPlan), as cache.py as_plan; n an Integer >= 1. Anything else is PBValidationError.
  aQuery pagerSize: n         PBPager on: aQuery pageSize: n (linq.py Queryable.pager)
  page: k                     rows k * n .. k * n + n - 1 as a new Array; an empty Array past the
                              last page; k an Integer >= 0, else PBValidationError
  rows, pages                 the exact number of rows, and of pages (0 for an empty result)
  byRank                      true when pages are sought by rank, O(log n + page size): the plan
                              knows its exact row count and offers rank access (plans.st
                              exactRows, byRank); false when they are sliced from one result
  explain                     a PBFrozenDict: 'pager' -> { 'page_size'. 'by_rank' } and 'plan' -> the
                              plan's explain (no 'portable': tokens are deferred, ruling CR7)
  plan, pageSize              the plan paged and the rows per page

A plan without rank access is executed once, when a page or rows first needs it, and its result
kept by the pager: the one mutable state, an Atom set once from nil (spec 12.6). Two actors asking
at the same moment may both execute the plan; one result is installed and every page is served
from it, so the pages always come from one result. proto_db takes a lock instead (pager.py
_materialized); the rows are the same either way, because the plan reads immutable versions. No
error is caught: an error of the plan reaches the caller of page: or rows."

Import from: 'protobase/errors'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/values'.
Import from: 'protobase/collections'.
Import from: 'protobase/plans'.
Import from: 'protobase/query'.

Object subclass: #PBPager instanceVariableNames: 'plan pageSize rows ranked result'.

"=== PBPager: construction (pager.py Pager.__init__, cache.py as_plan) ============="

"A pager of anInteger rows per page over aSource: a PBQueryPlan, a PBQuery or a
 PBIndexedCollection. PBValidationError for a page size that is not an Integer >= 1 (checked
 first, as pager.py does) or another source."
PBPager class >> on: aSource pageSize: anInteger
  | built exact |
  (anInteger isClassObject not and: [anInteger isInteger and: [anInteger >= 1]]) ifFalse: [
    ^ PBValidationError signal: 'A page size must be an Integer >= 1, not ' , (PBKeySpec _repr: anInteger)].
  built := self _planOf: aSource.
  exact := built exactRows.
  ^ self basicNew _setPlan: built pageSize: anInteger rows: exact
    ranked: (exact notNil and: [built byRank]).

"The plan of aSource (cache.py as_plan): a plan as is, a query's plan, a collection's scan."
PBPager class >> _planOf: aSource
  aSource isClassObject ifFalse: [
    (aSource isKindOf: PBQueryPlan) ifTrue: [^ aSource].
    (aSource isKindOf: PBQuery) ifTrue: [^ aSource plan].
    (aSource isKindOf: PBIndexedCollection) ifTrue: [^ aSource asQueryPlan]].
  ^ PBValidationError signal: 'PBPager on:pageSize: needs a PBQueryPlan, a PBQuery or a PBIndexedCollection, not '
    , (aSource isClassObject ifTrue: ['the class ' , aSource name] ifFalse: [PBKeySpec _repr: aSource]).

PBPager >> _setPlan: aPlan pageSize: anInteger rows: aRows ranked: aBoolean
  "Runs once, on a fresh instance."
  plan isNil ifFalse: [^ PBUserError signal: 'PBPager is immutable'].
  plan := aPlan.
  pageSize := anInteger.
  rows := aRows.
  ranked := aBoolean.
  result := Atom on: nil.
  ^ self.

"=== PBPager: accessors =========================================================="

"The plan whose rows are paged."
PBPager >> plan
  ^ plan.

"Rows per page."
PBPager >> pageSize
  ^ pageSize.

"True when pages are served by rank (O(log n + page size)), false when sliced from one result."
PBPager >> byRank
  ^ ranked.

"=== PBPager: pages (pager.py rows, pages, page) =================================="

"The plan's rows, executed once and kept (pager.py _materialized, without the cache)."
PBPager >> _materialized
  | rowsNow |
  rowsNow := result value.
  rowsNow isNil ifFalse: [^ rowsNow].
  result value: plan execute ifCurrent: nil.
  ^ result value.

"The exact number of rows."
PBPager >> rows
  ^ ranked ifTrue: [rows] ifFalse: [self _materialized size].

"The number of pages: 0 for an empty result."
PBPager >> pages
  ^ self rows + pageSize - 1 // pageSize.

"Page anInteger (from 0) as a new Array of rows; an empty Array past the last page.
 PBValidationError when anInteger is not an Integer >= 0."
PBPager >> page: anInteger
  | start stop all |
  (anInteger isClassObject not and: [anInteger isInteger and: [anInteger >= 0]]) ifFalse: [
    ^ PBValidationError signal: 'A page number must be an Integer >= 0, not ' , (PBKeySpec _repr: anInteger)].
  start := anInteger * pageSize.
  stop := start + pageSize.
  ranked ifTrue: [^ plan windowFrom: start to: stop].
  all := self _materialized.
  start >= all size ifTrue: [^ #()].
  ^ all copyFrom: start + 1 to: (stop min: all size).

"=== PBPager: explain and printing ==============================================="

"{ 'pager' -> { 'page_size'. 'by_rank' }. 'plan' -> the plan's explain } (pager.py explain, less
 'portable', ruling CR7)."
PBPager >> explain
  ^ PBFrozenDict withAssociations: {
    'pager' -> (PBFrozenDict withAssociations: { 'page_size' -> pageSize. 'by_rank' -> ranked }).
    'plan' -> plan explain }.

PBPager >> printOn: aStream
  aStream nextPutAll: 'PBPager(page size '; print: pageSize; nextPutAll: ', ';
    nextPutAll: (ranked ifTrue: ['by rank'] ifFalse: ['materialised']); nextPut: $).

"=== PBQuery >> pagerSize: (linq.py Queryable.pager) ============================="

"A PBPager of anInteger rows per page over this query's plan (PBPager on: self pageSize:)."
PBQuery >> pagerSize: anInteger
  ^ PBPager on: self pageSize: anInteger.
