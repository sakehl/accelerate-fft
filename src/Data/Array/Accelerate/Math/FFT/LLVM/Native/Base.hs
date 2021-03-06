{-# LANGUAGE GADTs               #-}
{-# LANGUAGE MagicHash           #-}
{-# LANGUAGE PatternGuards       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}
-- |
-- Module      : Data.Array.Accelerate.Math.FFT.LLVM.Native.Base
-- Copyright   : [2017] Manuel M T Chakravarty, Gabriele Keller, Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Data.Array.Accelerate.Math.FFT.LLVM.Native.Base
  where

import Data.Array.Accelerate.Array.Data
import Data.Array.Accelerate.Array.Sugar
import Data.Array.Accelerate.Array.Unique
import Data.Array.Accelerate.Data.Complex
import Data.Array.Accelerate.Lifetime

import Data.Array.Accelerate.Math.FFT.Mode
import Data.Array.Accelerate.Math.FFT.Type

import Data.Array.Accelerate.Math.FFT.LLVM.Native.Ix

import Data.Array.CArray.Base                                       ( CArray(..) )
import Math.FFT.Base                                                ( Sign(..), Flag, measure, preserveInput )

import Data.Bits
import Foreign.ForeignPtr
import Text.Printf
import Prelude                                                      as P


signOf :: Mode -> Sign
signOf Forward = DFTForward
signOf _       = DFTBackward

flags :: Flag
flags = measure .|. preserveInput

nameOf :: forall sh. Shape sh => Mode -> sh -> String
nameOf Forward _ = printf "FFTW.dft%dD"  (rank @sh)
nameOf _       _ = printf "FFTW.idft%dD" (rank @sh)


-- /O(1)/ Convert a CArray to an Accelerate array
--
{-# INLINE fromCArray #-}
fromCArray
    :: forall ix sh e. (IxShapeRepr (EltRepr ix) ~ EltRepr sh, Shape sh, Elt ix, Numeric e)
    => CArray ix (Complex e)
    -> IO (Array sh (Complex e))
fromCArray (CArray lo hi _ fp) = do
  --
  sh <- return $ rangeToShape (toIxShapeRepr lo, toIxShapeRepr hi) :: IO sh
  ua <- newUniqueArray (castForeignPtr fp :: ForeignPtr e)
  --
  case numericR::NumericR e of
    NumericRfloat32 -> return $ Array (fromElt sh) (AD_Vec 2# (AD_Float  ua))
    NumericRfloat64 -> return $ Array (fromElt sh) (AD_Vec 2# (AD_Double ua))

-- /O(1)/ Use an Accelerate array as a CArray
--
{-# INLINE withCArray #-}
withCArray
    :: forall ix sh e a. (IxShapeRepr (EltRepr ix) ~ EltRepr sh, Shape sh, Elt ix, Numeric e)
    => Array sh (Complex e)
    -> (CArray ix (Complex e) -> IO a)
    -> IO a
withCArray arr f =
  let
      sh        = shape arr
      (lo, hi)  = shapeToRange sh
      wrap fp   = CArray (fromIxShapeRepr lo) (fromIxShapeRepr hi) (size sh) (castForeignPtr fp)
  in
  withArray arr (f . wrap)


-- Use underlying array pointers
--
{-# INLINE withArray #-}
withArray
    :: forall sh e a. Numeric e
    => Array sh (Complex e)
    -> (ForeignPtr e -> IO a)
    -> IO a
withArray (Array _ adata) = withArrayData (numericR::NumericR e) adata

{-# INLINE withArrayData #-}
withArrayData
    :: NumericR e
    -> ArrayData (EltRepr (Complex e))
    -> (ForeignPtr e -> IO a)
    -> IO a
withArrayData NumericRfloat32 (AD_Vec _ (AD_Float  ua)) = withLifetime (uniqueArrayData ua)
withArrayData NumericRfloat64 (AD_Vec _ (AD_Double ua)) = withLifetime (uniqueArrayData ua)

