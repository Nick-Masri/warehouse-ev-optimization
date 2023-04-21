function [gridPowPrice] = initGridPricingModel(numDays)

% This function sets the price per kWh of grid electricity
%       time increment: 15 minutes

% Assume summer weekday pricing
%   Peak:       .15360 dollars per kwh     14:00 - 18:00
%   Off Peak:   .10738 dollars per kwh     00:00 - 14:00;    18:00 - 24:00

% Create list of prices for single day
gridPowPrice = zeros(1,96);
for t = 1:96
    minutes = 15*t;
    if ((minutes > 14*60) && (minutes <= 18*60))
        gridPowPrice(t) = .15360;
    else
        gridPowPrice(t) = .10738;
    end
end

% Extend list to proper number of days
gridPow_init = gridPowPrice;
for d = 1:numDays-1
    gridPowPrice = [gridPowPrice, gridPow_init]; %#ok<AGROW>
end


end

