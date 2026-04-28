//+------------------------------------------------------------------+
//| PatternManager.mqh                                               |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#property strict

#include "2.Config.mqh"

class PatternManager
{
private:
   struct PatternVote
   {
      bool              valid;
      ENUM_PATTERN_TYPE type;
      int               dir;       // 1 = buy, -1 = sell
      double            extreme;
      double            score;
      string            label;
   };

public:
   bool Detect(const MqlRates &rates[],
               const int shift,
               const double atrPoints,
               ENUM_PATTERN_TYPE &outType,
               int &outDir,
               double &outExtreme,
               string &outReason)
   {
      outType    = PATTERN_NONE;
      outDir     = 0;
      outExtreme = 0.0;
      outReason  = "";

      if(shift < 1 || atrPoints <= 0)
      {
         outReason = "Invalid shift/ATR";
         return false;
      }

      if(shift + 2 >= Bars(_Symbol, _Period))
      {
         outReason = "Insufficient bar history";
         return false;
      }

      PatternVote votes[5];
      for(int i = 0; i < 5; i++)
         ResetVote(votes[i]);

      EvaluatePinbar(rates, shift, atrPoints, votes[0]);
      EvaluateEngulfing(rates, shift, atrPoints, votes[1]);
      EvaluateBottom(rates, shift, atrPoints, votes[2]);
      EvaluateFakey(rates, shift, atrPoints, votes[3]);
      EvaluateInsideBar(rates, shift, atrPoints, votes[4]);

      double buyScore = 0.0;
      double sellScore = 0.0;
      int buyCount = 0;
      int sellCount = 0;

      for(int i = 0; i < 5; i++)
      {
         if(!votes[i].valid)
            continue;

         if(votes[i].dir == 1)
         {
            buyScore += votes[i].score;
            buyCount++;
         }
         else if(votes[i].dir == -1)
         {
            sellScore += votes[i].score;
            sellCount++;
         }
      }

      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;

      if(totalScore < 1.60)
      {
         outReason = StringFormat("Confluence weak | buy=%.2f sell=%.2f", buyScore, sellScore);
         return false;
      }

      if(dominanceGap < 0.35)
      {
         outReason = StringFormat("Confluence conflict | buy=%.2f sell=%.2f", buyScore, sellScore);
         return false;
      }

      outDir = (buyScore > sellScore) ? 1 : -1;

      int bestIdx = FindBestVote(votes, outDir);
      if(bestIdx < 0)
      {
         outReason = "No dominant directional pattern";
         return false;
      }

      outType    = votes[bestIdx].type;
      outExtreme = votes[bestIdx].extreme;

      string stack = BuildConfluenceLabel(votes, outDir);
      outReason = votes[bestIdx].label +
                  StringFormat(" | Confluence %.2f | %s", totalScore, stack);

      return true;
   }

private:
   void ResetVote(PatternVote &v)
   {
      v.valid   = false;
      v.type    = PATTERN_NONE;
      v.dir     = 0;
      v.extreme = 0.0;
      v.score   = 0.0;
      v.label   = "";
   }

   int FindBestVote(PatternVote &votes[], int dir)
   {
      int best = -1;
      double bestScore = 0.0;

      for(int i = 0; i < ArraySize(votes); i++)
      {
         if(!votes[i].valid || votes[i].dir != dir)
            continue;

         if(votes[i].score > bestScore)
         {
            bestScore = votes[i].score;
            best = i;
         }
      }
      return best;
   }

   string BuildConfluenceLabel(const PatternVote &votes[], int dir)
   {
      string txt = "";
      for(int i = 0; i < ArraySize(votes); i++)
      {
         if(!votes[i].valid || votes[i].dir != dir)
            continue;

         if(txt != "")
            txt += " + ";

         txt += votes[i].label;
      }
      return txt;
   }

   double CandleOpen(const MqlRates &rates[], int shift)  { return rates[shift].open;  }
   double CandleHigh(const MqlRates &rates[], int shift)  { return rates[shift].high;  }
   double CandleLow(const MqlRates &rates[], int shift)   { return rates[shift].low;   }
   double CandleClose(const MqlRates &rates[], int shift) { return rates[shift].close; }

   double CandleRange(const MqlRates &rates[], int shift)
   { return CandleHigh(rates, shift) - CandleLow(rates, shift);}

   double CandleBody(const MqlRates &rates[], int shift)
   { return MathAbs(CandleClose(rates, shift) - CandleOpen(rates, shift));}

   double UpperWick(const MqlRates &rates[], int shift)
   { return CandleHigh(rates, shift) - MathMax(CandleOpen(rates, shift), CandleClose(rates, shift));}

   double LowerWick(const MqlRates &rates[], int shift)
   { return MathMin(CandleOpen(rates, shift), CandleClose(rates, shift)) - CandleLow(rates, shift);}

   bool IsBullish(const MqlRates &rates[], int shift)
   {  return CandleClose(rates, shift) > CandleOpen(rates, shift);}

   bool IsBearish(const MqlRates &rates[], int shift)
   { return CandleClose(rates, shift) < CandleOpen(rates, shift);}

   bool IsInsideBar(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) < CandleHigh(rates, shift + 1) &&
             CandleLow(rates, shift)  > CandleLow(rates, shift + 1);
   }

   double NormalizeATRFactor(const double value, const double atrPoints)
   {
      double atrPrice = atrPoints * _Point;
      if(atrPrice <= 0.0)
         return 0.0;
      return value / atrPrice;
   }

   void AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double atrPoints, const int dir, double &score)
   {
      double range = CandleRange(rates, shift);
      if(range <= 0.0)
         return;

      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      double bodyPct = CandleBody(rates, shift) / range;
      double atrFactor = NormalizeATRFactor(range, atrPoints);

      if(wickPct >= 0.50) score += 0.20;
      if(wickPct >= 0.60) score += 0.10;
      if(bodyPct <= 0.35) score += 0.10;
      if(atrFactor >= 0.60) score += 0.10;
   }

   void AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score)
   {
      double prevClose = CandleClose(rates, shift + 1);
      double curClose  = CandleClose(rates, shift);

      if(dir == 1 && curClose > prevClose) score += 0.10;
      if(dir == -1 && curClose < prevClose) score += 0.10;
   }

   void EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double range = CandleRange(rates, shift);
      if(range <= 0.0) return;

      double bodyMid = (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
      double upper = UpperWick(rates, shift);
      double lower = LowerWick(rates, shift);

      int dir = 0;
      double extreme = 0.0;

      if(CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * 2.0 : _Point))
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if(CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * 2.0 : _Point))
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else return;

      vote.valid = true;
      vote.type = PATTERN_PINBAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = 1.00;
      vote.label = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";

      AddStrengthFromRejection(rates, shift, atrPoints, dir, vote.score);
      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double o1 = CandleOpen(rates, shift),     c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift + 1), c2 = CandleClose(rates, shift + 1);

      bool prevBearish = c2 < o2;
      bool prevBullish = c2 > o2;

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if(prevBearish && c1 > o1 && c1 > o2 && o1 < c2)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if(prevBullish && c1 < o1 && c1 < o2 && o1 > c2)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else return;

      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift + 1);
      if(body2 > 0.0 && body1 >= body2 * 1.20) score += 0.20;
      if(NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.70) score += 0.15;

      vote.valid = true;
      vote.type = PATTERN_ENGULFING;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Engulf Bull" : "Engulf Bear";

      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateBottom(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double h1 = CandleHigh(rates, shift);
      double l1 = CandleLow(rates, shift);
      double h2 = CandleHigh(rates, shift + 1);
      double l2 = CandleLow(rates, shift + 1);

      double tol = MathMax(atrPoints * 0.10 * _Point, 3 * _Point);

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if(MathAbs(l1 - l2) <= tol && IsBullish(rates, shift))
      {
         dir = 1;
         extreme = MathMin(l1, l2);
      }
      else if(MathAbs(h1 - h2) <= tol && IsBearish(rates, shift))
      {
         dir = -1;
         extreme = MathMax(h1, h2);
      }
      else return;

      if(NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.50) score += 0.10;
      if(CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= 0.35) score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_BOTTOM;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
   }

   void EvaluateFakey(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      // shift     : false-break candle
      double h0 = CandleHigh(rates, shift);
      double l0 = CandleLow(rates, shift);
      double c0 = CandleClose(rates, shift);
      double o0 = CandleOpen(rates, shift);
      // shift + 1 : inside bar
      double h1 = CandleHigh(rates, shift + 1);
      double l1 = CandleLow(rates, shift + 1);
      // shift + 2 : mother bar
      double h2 = CandleHigh(rates, shift + 2);
      double l2 = CandleLow(rates, shift + 2);

      bool insideStructure = (h1 < h2 && l1 > l2);
      if(!insideStructure) return;

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if(l0 < l1 && c0 > l1 && c0 > o0)
      {
         dir = 1;
         extreme = l0;
      }
      else if(h0 > h1 && c0 < h1 && c0 < o0)
      {
         dir = -1;
         extreme = h0;
      }
      else
         return;

      if(NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.60) score += 0.15;
      if(CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= 0.40) score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_FAKEY;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
   }

   void EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      if(!IsInsideBar(rates, shift))
         return;

      double motherHigh = CandleHigh(rates, shift + 1);
      double motherLow  = CandleLow(rates, shift + 1);
      double motherMid  = (motherHigh + motherLow) / 2.0;
      double childClose = CandleClose(rates, shift);
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if(childClose > motherMid)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if(childClose < motherMid)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      double motherRange = CandleRange(rates, shift + 1);
      double childRange  = CandleRange(rates, shift);

      if(motherRange > 0.0 && childRange / motherRange <= 0.65) score += 0.15;
      if(NormalizeATRFactor(motherRange, atrPoints) >= 0.70) score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_INSIDE_BAR_BREAKOUT;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Inside Bull" : "Inside Bear";
   }
};

#endif