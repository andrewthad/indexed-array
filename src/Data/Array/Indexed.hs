{-# language DataKinds #-}
{-# language DeriveFoldable #-}
{-# language DeriveFunctor #-}
{-# language DerivingStrategies #-}
{-# language ExplicitNamespaces #-}
{-# language GADTSyntax #-}
{-# language KindSignatures #-}
{-# language RankNTypes #-}
{-# language ScopedTypeVariables #-}
{-# language TypeApplications #-}
{-# language TypeOperators #-}

module Data.Array.Indexed
  ( Vector
  , MutableVector
  , index
  , read
  , write
  , length
  , copy
  , append
  , singleton
  , replicateM
  , unsafeFreeze
  , new
  , forget
  , with
  ) where

import Prelude hiding (read,length)

import Control.Monad.ST (ST,runST)
import Control.Monad.Primitive (PrimMonad,PrimState)
import Data.Arithmetic.Unsafe (Nat(Nat),type (<)(Lt), type (<=))
import Data.Primitive (Array,MutableArray)
import Data.Kind (Type)
import GHC.TypeNats (type (+))

import qualified Data.Arithmetic.Plus as Plus
import qualified Data.Arithmetic.Equal as Equal
import qualified Data.Arithmetic.Lt as Lt
import qualified Data.Primitive as PM
import qualified GHC.TypeNats as GHC
import qualified Data.Arithmetic.Nat as Nat

newtype Vector :: GHC.Nat -> Type -> Type where
  Vector :: Array a -> Vector n a
  deriving stock (Functor,Foldable)

newtype MutableVector :: Type -> GHC.Nat -> Type -> Type where
  MutableVector :: MutableArray s a -> MutableVector s n a

new ::
     Nat n
  -> ST s (MutableVector s n a)
{-# INLINE new #-}
-- this is not a core operation
new n = replicateM n errorThunk

replicateM ::
     Nat n
  -> a
  -> ST s (MutableVector s n a)
{-# INLINE replicateM #-}
-- this is a core operation
replicateM (Nat n) a = fmap MutableVector (PM.newArray n a)

singleton ::
     a
  -> Vector 1 a
{-# INLINE singleton #-}
singleton x = runST (replicateM Nat.one x >>= unsafeFreeze)

length :: Vector n a -> Nat n
{-# INLINE length #-}
-- this is a core operation
length (Vector x) = Nat (PM.sizeofArray x)

index ::
     (m < n) -- ^ Evidence the index is in-bounds
  -> Vector n a -- ^ Array
  -> Nat m -- ^ Index
  -> a
{-# INLINE index #-}
-- this is a core operation
index Lt (Vector arr) (Nat i) = PM.indexArray arr i

read ::
     (m < n) -- ^ Evidence the index is in-bounds
  -> MutableVector s n a -- ^ Array
  -> Nat m -- ^ Index
  -> ST s a
{-# INLINE read #-}
-- this is a core operation
read Lt (MutableVector arr) (Nat i) = PM.readArray arr i

write ::
     (m < n) -- ^ Evidence the index is in-bounds
  -> MutableVector s n a -- ^ Array
  -> Nat m -- ^ Index
  -> a
  -> ST s ()
{-# INLINE write #-}
-- this is a core operation
write Lt (MutableVector arr) (Nat i) x = PM.writeArray arr i x

-- | Freeze the mutable vector. The argument must not be reused after
-- this function is called on it. 
unsafeFreeze ::
     MutableVector s n a
  -> ST s (Vector n a)
{-# INLINE unsafeFreeze #-}
-- this is a core operation
unsafeFreeze (MutableVector marr) = do
  fmap Vector (PM.unsafeFreezeArray marr)

copy ::
     (doff + n <= dlen)
  -> (soff + n <= slen)
  -> MutableVector s dlen a -- ^ Destination
  -> Nat doff
  -> Vector slen a -- ^ Source
  -> Nat soff
  -> Nat n
  -> ST s ()
-- this is a core operation
copy Lt Lt (MutableVector dst) (Nat doff) (Vector src) (Nat soff) (Nat len) =
  PM.copyArray dst doff src soff len

append :: forall m n a. Vector m a -> Vector n a -> Vector (m + n) a
-- Not a core operation. Defined safely using other primitives.
append x y = runST $ do
  let xlen = length x
  let ylen = length y
  r <- new (Nat.plus xlen ylen)
  copy
    ( Lt.substituteR (Equal.symmetric (Plus.associative @m @n @1))
    $ Lt.plus @m (Lt.zero @n)
    )
    (Lt.plus @m (Lt.zero @0))
    r Nat.zero x Nat.zero xlen
  copy
    (Lt.plus @(m + n) (Lt.zero @0))
    (Lt.plus @n (Lt.zero @0))
    r xlen y Nat.zero ylen
  unsafeFreeze r

-- | Discard the phantom length associated with an indexed vector.
forget :: Vector n a -> Array a
{-# INLINE forget #-}
-- This is a core operation
forget (Vector arr) = arr

errorThunk :: a
{-# NOINLINE errorThunk #-}
errorThunk = error "Data.Array.Indexed: uninitialized element"

with :: Array a -> (forall n. Vector n a -> b) -> b
with x f = f (Vector x)
