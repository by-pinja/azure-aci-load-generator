const puppeteer = require('puppeteer')

let browser
let page

before(async () => {
    let isHeadless = process.env.CHROME_HEADLESS ? true : false

    browser = await puppeteer.launch({
        executablePath: process.env.CHROME_PATH,
        headless: isHeadless,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--ignore-certificate-errors', '--incognito']
    });
    page = await browser.newPage()
})

describe('Example', () => {
    it('Logins page? Something else maybe? Create data, behave like real user etc"', async () => {
        await page.goto(`https://exampleuriheregoesnowhere.fi/`);
        await page.waitForSelector('#userName');
        await page.type('#userName', 'foo');
        await page.type('#password', 'bar');
        await page.waitForSelector('#login-button');
        await page.click('#login-button');
    })
})

after(async () => {
    await browser.close()
})
