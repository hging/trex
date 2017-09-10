1+1;
var grio = grio || {};
grio.getCookies = {
	webpage:	false,
	page:		false,
	url:		false,
	userAgent:	false,
	init: function() {
		this.webpage	= require('webpage');
		this.page		= this.webpage.create();
		this.url		= 'http://bittrex.com';
		this.userAgent	= 'Mozilla/5.0 (Windows NT 6.3; rv:36.0) Gecko/20100101 Firefox/36.0';
		this.timeout	= 6000;
	},
	visit: function() {
		var self = this;
		userAgent = this.page.settings.userAgent = this.userAgent;
		this.page.open(this.url, function(status) {
			setTimeout(function() {
				console.log(JSON.stringify({userAgent: userAgent, cookies: phantom.cookies}));
				phantom.exit()
			}, self.timeout);
		});
	}
}
grio.getCookies.init();
grio.getCookies.visit();
