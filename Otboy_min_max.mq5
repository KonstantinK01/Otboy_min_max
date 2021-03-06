//+------------------------------------------------------------------+
//|                                                Otboy_min_max.mq5 |
//|                                                       Konstantin |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Konstantin"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input ENUM_TIMEFRAMES      Period = 15;     //Период
input int      Lot=1;                       //Размер открываемой позиции
input double   Take=900;                    //Тэйк профит
input double   Stop=300;                    //Стоп лосс
input int MinMaxPeriod = 50;                //Ширина окна поиска min and max
input int RangePeriod = 40;                 //Период за который не изменился экстремум.(в %)
input double RangeIn = 0.1;                 //Допустимый диапозон от min/max (в %)

//-------Глобальные переменные
int MinMaxHandle;                          // хэндл индикатора
double STP,TKP;
string short_name;                 // имя индикатора на графике
double MinPeriod[],MaxPeriod[];
double MinValidRangeUp,MinValidRangeDown;
double MaxValidRangeUp,MaxValidRangeDown;
double MinUnchangedExtremum,MaxUnchangedExtremum;
int UnchangedExtremum;

CTrade m_Trade;
CPositionInfo     m_Position;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   UnchangedExtremum = MinMaxPeriod * RangePeriod/100;
   if(UnchangedExtremum > MinMaxPeriod)
     {
      Alert("Ширина окна поиска min and max должно быть больше чем период за который не изменился экстремум ");
      return(-1);
     }
//---Получим хэндл индикатора
   MinMaxHandle = iCustom(_Symbol,Period,"MaxMinOfThePreviousBar",MinMaxPeriod);

   if(MinMaxHandle<0)
     {
      Alert("Ошибка при создании индикаторов - номер ошибки: ",GetLastError(),"!!");
      return(-1);
     }
   ChartIndicatorAdd(ChartID(),0,MinMaxHandle);
   short_name=StringFormat("MaxMinOfThePreviousBar(%s/%s, %G)",_Symbol,EnumToString(Period),MinMaxPeriod);
   IndicatorSetString(INDICATOR_SHORTNAME,short_name);

   STP = Stop;
   TKP = Take;
   if(_Digits==5 || _Digits==3)
     {
      STP = STP*10.0;
      TKP = TKP*10.0;
     }

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

   if(!ChartIndicatorDelete(ChartID(),0,short_name))
     {
      PrintFormat("Не удалось удалить индикатор %s с окна #%d. Код ошибки %d",short_name,0,GetLastError());
     }
//--- Освобождаем хэндлы индикаторов
   IndicatorRelease(MinMaxHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

//--- Достаточно ли количество баров для работы
   if(Bars(_Symbol,Period)<MinMaxPeriod)
     {
      PrintFormat("На графике меньше %G баров, советник не будет работать!!",MinMaxPeriod);
      return;
     }

   static datetime Old_Time;
   datetime New_Time[1];
   bool IsNewBar=false;

// копируем время текущего бара в элемент New_Time[0]
   int copied=CopyTime(_Symbol,Period,0,1,New_Time);
   if(copied>0)
     {
      if(Old_Time!=New_Time[0])
        {
         IsNewBar=true;
         if(MQL5InfoInteger(MQL5_DEBUGGING))
            PrintFormat("Новый бар ",New_Time[0]," старый бар ",Old_Time);
         Old_Time=New_Time[0];
        }
     }
   else
     {
      PrintFormat("Ошибка копирования времени, номер ошибки =",GetLastError());
      ResetLastError();
      return;
     }

//--- советник должен проверять условия совершения новой торговой операции только при новом баре
   if(IsNewBar==false)
     {
      return;
     }

   MqlRates mrate[];                  // Будет содержать цены, объемы и спред для каждого бара
   ArraySetAsSeries(mrate,true);
   ArraySetAsSeries(MinPeriod,true);
   ArraySetAsSeries(MaxPeriod,true);

   if(CopyRates(_Symbol,Period,0,3,mrate)<0)
     {
      PrintFormat("Ошибка копирования исторических данных - ошибка:",GetLastError(),"!!");
      return;
     }

   if(CopyBuffer(MinMaxHandle,1,0,UnchangedExtremum,MinPeriod)<0)      // Значения минимума лежат в 1.
     {
      PrintFormat("Ошибка копирования буферов индикатора MaxMinOfThePreviousBar - номер ошибки:",GetLastError());
      return;
     }

   if(CopyBuffer(MinMaxHandle,0,0,UnchangedExtremum,MaxPeriod)<0)      // Значения максимума лежат в 0.
     {
      PrintFormat("Ошибка копирования буферов индикатора MaxMinOfThePreviousBar - номер ошибки:",GetLastError());
      return;
     }
//1.Покупка:
   MinValidRangeDown = MinPeriod[3] - MinPeriod[3]*(RangeIn/100);
   MinValidRangeUp = MinPeriod[3] + MinPeriod[3]*(RangeIn/100);
   MinUnchangedExtremum = MinPeriod[UnchangedExtremum-1] - MinPeriod[3];

   string symbol = _Symbol;                                      // укажем символ, на котором выставляется ордер
   int    digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS); // количество знаков после запятой
   double point = SymbolInfoDouble(symbol,SYMBOL_POINT);         // пункт

   if(mrate[2].close <= MinValidRangeUp && mrate[2].close >= MinValidRangeDown && mrate[1].open < mrate[1].close && mrate[0].close >= MinValidRangeUp && MinUnchangedExtremum == 0)
     {
      if(m_Position.Select(_Symbol))                             //если уже существует позиция по этому символу
        {
         if(m_Position.PositionType()==POSITION_TYPE_SELL)
           {
            m_Trade.PositionClose(symbol);
           }
         if(m_Position.PositionType()==POSITION_TYPE_BUY)
           {
            return;
           }
        }
      double ask = SymbolInfoDouble(symbol,SYMBOL_ASK);
      double price_stop = ask-STP*point;
      double price_take = ask+TKP*point;
      price_stop =NormalizeDouble(price_stop,digits);
      price_take =NormalizeDouble(price_take,digits);
      m_Trade.Buy(Lot,_Symbol,0.0,price_stop,price_take);
     }
//2.Продажа:
   MaxValidRangeDown = MaxPeriod[3] - MaxPeriod[3]*(RangeIn/100);
   MaxValidRangeUp = MaxPeriod[3] + MaxPeriod[3]*(RangeIn/100);
   MaxUnchangedExtremum = MaxPeriod[UnchangedExtremum-1] - MaxPeriod[3];

   if(mrate[2].close <= MaxValidRangeUp && mrate[2].close >= MaxValidRangeDown && mrate[1].open > mrate[1].close && mrate[0].close <= MaxValidRangeDown && MaxUnchangedExtremum == 0)
     {
      if(m_Position.Select(_Symbol))                             //если уже существует позиция по этому символу
        {
         if(m_Position.PositionType()==POSITION_TYPE_SELL)
           {
            return;
           }
         if(m_Position.PositionType()==POSITION_TYPE_BUY)
           {
            m_Trade.PositionClose(symbol);
           }
        }
      double bid = SymbolInfoDouble(symbol,SYMBOL_BID);
      double price_stop  = bid+STP*point;
      double price_take  = bid-TKP*point;
      price_take = NormalizeDouble(price_take,digits);
      price_stop = NormalizeDouble(price_stop,digits);
      m_Trade.Sell(Lot,_Symbol,0.0,price_stop,price_take);
     }
  }
//+------------------------------------------------------------------+
