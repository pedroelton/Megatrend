//+------------------------------------------------------------------+
//|                                                    Megatrend.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Megatrend Strategy"
#property link      ""
#property version   "1.00"
#property strict

input bool    EnterAtStart = true;          // Enter Position at Start
input int     ATR_Period1 = 10;             // ST1 ATR Period
input double  Factor1 = 1.0;                // ST1 Factor
input int     ATR_Period2 = 11;             // ST2 ATR Period
input double  Factor2 = 2.0;                // ST2 Factor
input int     ATR_Period3 = 12;             // ST3 ATR Period
input double  Factor3 = 3.0;                // ST3 Factor
input double  LotSize = 0.1;                // Lot Size
input int     MagicNumber = 123456;         // Magic Number

// Supertrend arrays
double st1[], st2[], st3[];
int dir1[], dir2[], dir3[];
int prev_dir1[], prev_dir2[], prev_dir3[];

// Position state: 0=none, 1=full long, 2=2/3 long, 3=1/3 long, -1=full short, -2=2/3 short, -3=1/3 short
int positionState = 0;
bool hasEnteredFirstTrade = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ArraySetAsSeries(st1, true);
   ArraySetAsSeries(st2, true);
   ArraySetAsSeries(st3, true);
   ArraySetAsSeries(dir1, true);
   ArraySetAsSeries(dir2, true);
   ArraySetAsSeries(dir3, true);
   ArraySetAsSeries(prev_dir1, true);
   ArraySetAsSeries(prev_dir2, true);
   ArraySetAsSeries(prev_dir3, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculate Supertrend                                             |
//+------------------------------------------------------------------+
void CalculateSupertrend(double &st[], int &dir[], int atr_period, double factor)
{
   int rates_total = Bars(_Symbol, _Period);
   ArrayResize(st, rates_total);
   ArrayResize(dir, rates_total);
   
   double atr[], hl2[];
   ArrayResize(atr, rates_total);
   ArrayResize(hl2, rates_total);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(hl2, true);
   
   int atr_handle = iATR(_Symbol, _Period, atr_period);
   CopyBuffer(atr_handle, 0, 0, rates_total, atr);
   
   for(int i = rates_total - 1; i >= 0; i--)
   {
      double high = iHigh(_Symbol, _Period, i);
      double low = iLow(_Symbol, _Period, i);
      double close = iClose(_Symbol, _Period, i);
      
      hl2[i] = (high + low) / 2.0;
      
      double basic_ub = hl2[i] + factor * atr[i];
      double basic_lb = hl2[i] - factor * atr[i];
      
      double final_ub = basic_ub;
      double final_lb = basic_lb;
      
      if(i < rates_total - 1)
      {
         final_ub = (basic_ub < st[i+1] || iClose(_Symbol, _Period, i+1) > st[i+1]) ? basic_ub : st[i+1];
         final_lb = (basic_lb > st[i+1] || iClose(_Symbol, _Period, i+1) < st[i+1]) ? basic_lb : st[i+1];
      }
      
      if(i < rates_total - 1)
      {
         if(st[i+1] == final_ub)
            dir[i] = (close <= final_ub) ? 1 : -1;
         else
            dir[i] = (close >= final_lb) ? -1 : 1;
      }
      else
         dir[i] = 1;
      
      st[i] = (dir[i] == 1) ? final_ub : final_lb;
   }
   
   IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Check if all trends are aligned                                 |
//+------------------------------------------------------------------+
bool AllUptrend()
{
   return (dir1[0] == -1 && dir2[0] == -1 && dir3[0] == -1);
}

bool AllDowntrend()
{
   return (dir1[0] == 1 && dir2[0] == 1 && dir3[0] == 1);
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type, string comment)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = order_type;
   request.price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = comment;
   
   OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Close position partially                                         |
//+------------------------------------------------------------------+
void ClosePositionPartial(double percent, string comment)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double close_volume = NormalizeDouble(volume * percent / 100.0, 2);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = close_volume;
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = MagicNumber;
            request.comment = comment;
            
            OrderSend(request, result);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string comment)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = MagicNumber;
            request.comment = comment;
            
            OrderSend(request, result);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Calculate all three Supertrends
   CalculateSupertrend(st1, dir1, ATR_Period1, Factor1);
   CalculateSupertrend(st2, dir2, ATR_Period2, Factor2);
   CalculateSupertrend(st3, dir3, ATR_Period3, Factor3);
   
   // Store previous directions
   if(ArraySize(prev_dir1) > 1)
   {
      prev_dir1[0] = dir1[1];
      prev_dir2[0] = dir2[1];
      prev_dir3[0] = dir3[1];
   }
   
   // Detect flips
   bool st1_flip_to_down = (dir1[0] == 1 && prev_dir1[0] == -1);
   bool st1_flip_to_up = (dir1[0] == -1 && prev_dir1[0] == 1);
   
   bool st2_flip_to_down = (dir2[0] == 1 && prev_dir2[0] == -1);
   bool st2_flip_to_up = (dir2[0] == -1 && prev_dir2[0] == 1);
   
   bool st3_flip_to_down = (dir3[0] == 1 && prev_dir3[0] == -1);
   bool st3_flip_to_up = (dir3[0] == -1 && prev_dir3[0] == 1);
   
   // Initial entry
   if(!hasEnteredFirstTrade && EnterAtStart)
   {
      if(AllUptrend())
      {
         OpenPosition(ORDER_TYPE_BUY, "Long Entry");
         positionState = 1;
         hasEnteredFirstTrade = true;
      }
      else if(AllDowntrend())
      {
         OpenPosition(ORDER_TYPE_SELL, "Short Entry");
         positionState = -1;
         hasEnteredFirstTrade = true;
      }
   }
   
   // LONG ENTRY: All 3 lines flip to uptrend
   if(st3_flip_to_up && AllUptrend() && positionState == 0)
   {
      OpenPosition(ORDER_TYPE_BUY, "Long Entry");
      positionState = 1;
      hasEnteredFirstTrade = true;
   }
   
   // SHORT ENTRY: All 3 lines flip to downtrend
   if(st3_flip_to_down && AllDowntrend() && positionState == 0)
   {
      OpenPosition(ORDER_TYPE_SELL, "Short Entry");
      positionState = -1;
      hasEnteredFirstTrade = true;
   }
   
   // LONG POSITION EXITS
   if(positionState == 1 && st1_flip_to_down)
   {
      ClosePositionPartial(33.33, "Close 1/3 Long");
      positionState = 2;
   }
   
   if(positionState == 2 && st2_flip_to_down)
   {
      ClosePositionPartial(50.0, "Close 2/3 Long");
      positionState = 3;
   }
   
   if(positionState == 3 && st3_flip_to_down)
   {
      CloseAllPositions("Close 3/3 Long");
      positionState = 0;
      
      if(AllDowntrend())
      {
         OpenPosition(ORDER_TYPE_SELL, "Short Entry");
         positionState = -1;
      }
   }
   
   // SHORT POSITION EXITS
   if(positionState == -1 && st1_flip_to_up)
   {
      ClosePositionPartial(33.33, "Close 1/3 Short");
      positionState = -2;
   }
   
   if(positionState == -2 && st2_flip_to_up)
   {
      ClosePositionPartial(50.0, "Close 2/3 Short");
      positionState = -3;
   }
   
   if(positionState == -3 && st3_flip_to_up)
   {
      CloseAllPositions("Close 3/3 Short");
      positionState = 0;
      
      if(AllUptrend())
      {
         OpenPosition(ORDER_TYPE_BUY, "Long Entry");
         positionState = 1;
      }
   }
}
//+------------------------------------------------------------------+