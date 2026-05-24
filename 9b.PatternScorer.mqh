//+------------------------------------------------------------------+
//| PatternScorer.mqh — Logistic Regression-based Pattern Score     |
//| Menggantikan sistem bonus flat (+0.10, +0.20) dengan            |
//| probabilitas win berbasis koefisien regresi logistik.           |
//|                                                                  |
//| Output: double 0.0-1.0 = estimasi probabilitas win              |
//| Threshold entry: score >= CFG.MinPatternScore (default 0.60)    |
//|                                                                  |
//| CARA INTEGRASI KE PatternManager:                               |
//| 1. #include "9b.PatternScorer.mqh"                              |
//| 2. Di setiap EvaluateXxx(), ganti:                              |
//|      vote.score = 1.00; + bonus manual                          |
//|    Dengan:                                                       |
//|      vote.score = ScoreXxx(rates, shift, atrPoints, srLevel);   |
//| 3. Sesuaikan threshold confluence di Detect():                  |
//|      totalScore < 1.60 → totalScore < 0.60                      |
//|      dominanceGap < 0.35 → dominanceGap < 0.10                  |
//+------------------------------------------------------------------+
#ifndef __PATTERN_SCORER_MQH__
#define __PATTERN_SCORER_MQH__

#property strict

// Helper: fungsi sigmoid (inverse logit)
// Output 0.0-1.0 = probabilitas win
double Sigmoid(double z)
{
   return 1.0 / (1.0 + MathExp(-z));
}

// Helper: hitung jarak harga ke zona S/R dalam satuan ATR
// Makin kecil = makin dekat = lebih baik (koefisien negatif di semua pola)
double CalcSRDistance(double price, double srLevel, double atrPoints)
{
   if(atrPoints <= 0 || srLevel <= 0) return 1.0;
   return MathAbs(price - srLevel) / (atrPoints * _Point);
}

//------------------------------------------------------------------
// PINBAR SCORER
//
// Variabel independen:
//   wick_ratio     (+) Wick utama / range candle         → kekuatan penolakan
//   atr_factor     (+) Range candle / ATR                → ukuran relatif
//   follow_through (+) Close[0] lebih ekstrem dari [1]  → konfirmasi arah
//   body_ratio     (-) Body / range                     → body kecil lebih baik
//   sr_distance    (-) Jarak ke S/R dalam ATR           → makin dekat makin baik
//
// Target win rate (kondisi median): 68%
// Intercept dikalibrasi: +0.343
//------------------------------------------------------------------
double ScorePinbar(const MqlRates &rates[], int shift,
                   double atrPoints, double srLevel)
{
   double range = rates[shift].high - rates[shift].low;
   if(range <= 0) return 0;

   double bodyMid = (rates[shift].open + rates[shift].close) / 2.0;
   int dir = (rates[shift].close > bodyMid) ? 1 : -1;

   double majorWick = (dir == 1)
      ? (MathMin(rates[shift].open, rates[shift].close) - rates[shift].low)
      : (rates[shift].high - MathMax(rates[shift].open, rates[shift].close));

   double wick_ratio     = majorWick / range;
   double body_ratio     = MathAbs(rates[shift].close - rates[shift].open) / range;
   double atr_factor     = (atrPoints > 0) ? range / (atrPoints * _Point) : 0;
   double follow_through = (dir == 1 && rates[shift].close > rates[shift+1].close) ? 1.0
                         : (dir == -1 && rates[shift].close < rates[shift+1].close) ? 1.0 : 0.0;
   double sr_distance    = CalcSRDistance(rates[shift].close, srLevel, atrPoints);

   double z = 0.343
      + 0.580 * wick_ratio
      + 0.225 * atr_factor
      + 0.207 * follow_through
      - 0.127 * body_ratio
      - 0.860 * sr_distance;

   return Sigmoid(z);
}

//------------------------------------------------------------------
// ENGULFING SCORER
//
// Variabel independen:
//   body_size_mult (+) Body[0] / Body[1]                → seberapa besar engulfing
//   follow_through (+) Konfirmasi arah
//   body_ratio     (+) Body / range (body besar = valid)
//   atr_factor     (+) Range / ATR
//   sr_distance    (-) Jarak ke S/R
//
// Target win rate: 58%
// Intercept: -0.763
//------------------------------------------------------------------
double ScoreEngulfing(const MqlRates &rates[], int shift,
                      double atrPoints, double srLevel)
{
   double range1 = rates[shift].high - rates[shift].low;
   if(range1 <= 0) return 0;

   double body1 = MathAbs(rates[shift].close - rates[shift].open);
   double body2 = MathAbs(rates[shift+1].close - rates[shift+1].open);
   int dir = (rates[shift].close > rates[shift].open) ? 1 : -1;

   double body_size_mult = (body2 > 0) ? body1 / body2 : 1.0;
   double body_ratio     = (range1 > 0) ? body1 / range1 : 0;
   double atr_factor     = (atrPoints > 0) ? range1 / (atrPoints * _Point) : 0;
   double follow_through = (dir == 1 && rates[shift].close > rates[shift+1].close) ? 1.0
                         : (dir == -1 && rates[shift].close < rates[shift+1].close) ? 1.0 : 0.0;
   double sr_distance    = CalcSRDistance(rates[shift].close, srLevel, atrPoints);

   double z = -0.763
      + 0.550 * body_size_mult
      + 0.277 * follow_through
      + 0.250 * body_ratio
      + 0.160 * atr_factor
      - 0.121 * sr_distance;

   return Sigmoid(z);
}

//------------------------------------------------------------------
// FAKEY SCORER
//
// Variabel independen:
//   close_strength  (+) Posisi close dalam range (arah berlawanan false break)
//   false_break_ext (+) Seberapa jauh melampaui inside bar (ATR units)
//   atr_factor      (+) Range / ATR
//   body_ratio      (+) Body / range
//   sr_distance     (-) Jarak ke S/R
//
// Target win rate: 72% (tertinggi)
// Intercept: +0.312
//------------------------------------------------------------------
double ScoreFakey(const MqlRates &rates[], int shift,
                  double atrPoints, double srLevel)
{
   // shift=false-break candle, shift+1=inside bar, shift+2=mother bar
   double range0 = rates[shift].high - rates[shift].low;
   if(range0 <= 0) return 0;

   int dir = (rates[shift].close > rates[shift].open) ? 1 : -1;

   double false_break_ext = (dir == 1)
      ? (rates[shift+1].low - rates[shift].low) / (atrPoints * _Point)
      : (rates[shift].high - rates[shift+1].high) / (atrPoints * _Point);
   false_break_ext = MathMax(false_break_ext, 0);

   double close_strength = (dir == 1)
      ? (rates[shift].close - rates[shift].low) / range0
      : (rates[shift].high - rates[shift].close) / range0;

   double body_ratio  = MathAbs(rates[shift].close - rates[shift].open) / range0;
   double atr_factor  = range0 / (atrPoints * _Point);
   double sr_distance = CalcSRDistance(rates[shift].close, srLevel, atrPoints);

   double z = 0.312
      + 0.470 * close_strength
      + 0.359 * false_break_ext
      + 0.182 * atr_factor
      + 0.162 * body_ratio
      - 0.166 * sr_distance;

   return Sigmoid(z);
}

//------------------------------------------------------------------
// TWEEZER SCORER
//
// Variabel independen:
//   low_match_prec (+) Presisi matching low/high (0–1, 1=sempurna)
//   volume_confirm (+) Volume candle sinyal > candle sebelumnya
//   atr_factor     (+) Range / ATR
//   body_candle2   (+) Body candle ke-2 / range-nya
//   sr_distance    (-) Jarak ke S/R
//
// Target win rate: 52%
// Intercept: -0.566
//------------------------------------------------------------------
double ScoreTweezer(const MqlRates &rates[], int shift,
                    double atrPoints, double srLevel)
{
   double range0 = rates[shift].high - rates[shift].low;
   double range1 = rates[shift+1].high - rates[shift+1].low;
   if(range0 <= 0 || range1 <= 0) return 0;

   int dir = (MathAbs(rates[shift].low - rates[shift+1].low) <
              MathAbs(rates[shift].high - rates[shift+1].high)) ? 1 : -1;

   double tol = MathAbs(dir == 1
      ? rates[shift].low - rates[shift+1].low
      : rates[shift].high - rates[shift+1].high);
   double low_match_prec  = 1.0 - MathMin(tol / MathMax(atrPoints * _Point * 0.1, _Point), 1.0);
   double body_candle2    = MathAbs(rates[shift+1].close - rates[shift+1].open) / range1;
   double atr_factor      = range0 / (atrPoints * _Point);
   double sr_distance     = CalcSRDistance(rates[shift].close, srLevel, atrPoints);
   double volume_confirm  = (rates[shift].tick_volume > rates[shift+1].tick_volume) ? 1.0 : 0.0;

   double z = -0.566
      + 0.440 * low_match_prec
      + 0.229 * volume_confirm
      + 0.203 * atr_factor
      + 0.186 * body_candle2
      - 0.125 * sr_distance;

   return Sigmoid(z);
}

//------------------------------------------------------------------
// INSIDE BAR SCORER
//
// Variabel independen:
//   trend_alignment (+) HTF alignment * dir (-1/0/+1)
//   mother_size     (+) Mother bar range / ATR
//   child_position  (-) Posisi close child dalam mother range
//   sr_distance     (-) Jarak ke S/R
//   child_mother    (-) Child range / mother range (makin kecil makin baik)
//
// Target win rate: 48% (terendah di ranging, butuh HTF alignment)
// Intercept: -0.373
//------------------------------------------------------------------
double ScoreInsideBar(const MqlRates &rates[], int shift,
                      double atrPoints, double srLevel,
                      int htfAlignment = 0)
{
   double motherRange = rates[shift+1].high - rates[shift+1].low;
   double childRange  = rates[shift].high - rates[shift].low;
   if(motherRange <= 0) return 0;

   int dir = (rates[shift].close > (rates[shift+1].high + rates[shift+1].low) / 2.0) ? 1 : -1;

   double trend_alignment = (double)(htfAlignment * dir);
   double mother_size     = motherRange / (atrPoints * _Point);
   double child_mother    = (motherRange > 0) ? childRange / motherRange : 1.0;
   double child_position  = (dir == 1)
      ? (rates[shift].close - rates[shift+1].low)  / motherRange
      : (rates[shift+1].high - rates[shift].close) / motherRange;
   double sr_distance     = CalcSRDistance(rates[shift].close, srLevel, atrPoints);

   double z = -0.373
      + 0.500 * trend_alignment
      + 0.235 * mother_size
      - 0.022 * child_position
      - 0.250 * sr_distance
      - 0.108 * child_mother;

   return Sigmoid(z);
}

#endif // __PATTERN_SCORER_MQH__
